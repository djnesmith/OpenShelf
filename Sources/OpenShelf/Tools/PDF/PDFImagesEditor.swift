import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension PDFTools {
    static let imageResolutions: [Double] = [72, 150, 300, 600]

    /// The pages in `text` ("1-3, 5"; empty for all), 0-based, each once and in order.
    static func selectedPages(_ text: String, pageCount: Int) -> Result<[Int], RangeError> {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .success(Array(0..<pageCount)) }
        return ranges(text, pageCount: pageCount).map { Array(Set($0.joined())).sorted() }
    }

    /// Saves each of `pages` (0-based) as "<name> Page N.png" (or JPEG) at `dpi`.
    static func exportImages(of url: URL, pages: [Int], as type: UTType, dpi: Double) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let document = try open(url)
            let pathExtension = type.preferredFilenameExtension ?? "png"
            return try pages.map { index in
                try Task.checkCancellation()
                guard let page = document.page(at: index), let image = PDFConversion.renderPage(page, dpi: dpi) else {
                    throw ConversionError.failed("Page \(index + 1) couldn’t be drawn.")
                }
                let destination = OutputNaming.destination(for: url, suffix: "Page \(index + 1)", pathExtension: pathExtension)
                try EditableImage.write(image, to: destination, type: type, quality: 0.92)
                return destination
            }
        }.value
    }
}

/// Saves chosen pages of a PDF as PNG or JPEG images at a chosen resolution.
struct PDFImagesEditor: View {
    static let windowSize = CGSize(width: 420, height: 290)

    let actions: EditorActions
    @State private var model: PDFImagesModel

    init(url: URL, actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: PDFImagesModel(url: url))
    }

    var body: some View {
        EditorChrome(
            title: "Save Pages as Images",
            primaryTitle: "Save",
            isPrimaryEnabled: !model.isSaving && model.pageError == nil,
            actions: actions,
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(model.url.lastPathComponent) · \(model.pageCount) pages")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Pages") {
                    TextField("All", text: $model.pages, prompt: Text("All, or e.g. 1-3, 5"))
                }
                if let error = model.pageError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                EditorRow(label: "Format") {
                    Picker("Format", selection: $model.type) {
                        Text("PNG").tag(UTType.png)
                        Text("JPEG").tag(UTType.jpeg)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                EditorRow(label: "Resolution") {
                    Picker("Resolution", selection: $model.dpi) {
                        ForEach(PDFTools.imageResolutions, id: \.self) { Text("\(Int($0)) dpi").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
            }
        }
    }
}

@MainActor
@Observable
final class PDFImagesModel {
    let url: URL
    let pageCount: Int
    var pages = ""
    var type = UTType.png
    var dpi: Double = 150
    private(set) var isSaving = false

    init(url: URL) {
        self.url = url
        pageCount = PDFDocument(url: url)?.pageCount ?? 0
    }

    var pageError: String? {
        if case .failure(let error) = PDFTools.selectedPages(pages, pageCount: pageCount) { return error.message }
        return nil
    }

    func save(actions: EditorActions) {
        guard case .success(let selected) = PDFTools.selectedPages(pages, pageCount: pageCount) else { return }
        isSaving = true
        let url = url
        let type = type
        let dpi = dpi
        Task { [weak self] in
            do {
                actions.saved(try await PDFTools.exportImages(of: url, pages: selected, as: type, dpi: dpi))
            } catch {
                self?.isSaving = false
                actions.failed(error)
            }
        }
    }
}
