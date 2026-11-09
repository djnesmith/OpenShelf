import Foundation
import PDFKit

/// A fillable copy of a plain PDF, saved as "name.fillable.pdf" next to the
/// original. commonforms (`uv tool install commonforms`) finds the blanks,
/// boxes and signature lines with a small vision model and adds form fields.
///
/// It runs on a copy in an empty temp folder that is also its HOME, with the
/// child-process allowlist. Its libraries phone home unless told not to:
/// ultralytics sends an analytics event on every run, checks it's online and
/// pip-installs what it misses; huggingface_hub asks for a newer model each
/// run and sends a saved login token. The environment turns all of that off.
enum MakeFillable {
    /// Tried first: it downloads 18 MB, not 49, and found more fields than L
    /// on image-only pages. It can find nothing on a typed form L fills.
    static let model = "FFDNet-S"
    /// The CLI's default, run only when the small model finds no fields.
    static let largeModel = "FFDNet-L"
    static let modelDownloadNote = "Downloading the form model, 18 MB, first time only"
    static let largeModelDownloadNote = "May download a larger form model, 49 MB, if the first finds nothing"
    static let scannedNote = "Scanned pages may miss most fields"
    /// Refused: commonforms finds the old fields' blanks again and stacks a
    /// same-named field on each one.
    static let alreadyFillableNote = "This PDF is already fillable"

    /// - Parameter keepingExisting: The PDF has annotations. commonforms
    ///   otherwise deletes every one, links and comments included.
    static func arguments(input: URL, output: URL, keepingExisting: Bool, model: String = MakeFillable.model) -> [String] {
        [input.path, output.path, "--model", model, "--use-signature-fields"]
            + (keepingExisting ? ["--keep-existing-fields"] : [])
    }

    /// The minimal environment, with HOME in `folder`. Hugging Face stays
    /// offline once the model is in `huggingFaceHome`; before that, the run
    /// downloads it.
    static func environment(folder: URL, huggingFaceHome: URL, isModelCached: Bool) -> [String: String] {
        var extra = [
            "HOME": folder.path, "TMPDIR": folder.path, "XDG_CONFIG_HOME": folder.path,
            // "true", not "1": ultralytics 8.3 (commonforms allows >=8.3.204) only accepts "true".
            "YOLO_OFFLINE": "true", "YOLO_AUTOINSTALL": "0", "YOLO_CONFIG_DIR": folder.path,
            "HF_HOME": huggingFaceHome.path, "HF_HUB_DISABLE_TELEMETRY": "1", "HF_HUB_DISABLE_IMPLICIT_TOKEN": "1",
        ]
        if isModelCached {
            extra["HF_HUB_OFFLINE"] = "1"
        }
        return ChildEnvironment.minimal(extra: extra)
    }

    /// Where huggingface_hub keeps models when nothing overrides it.
    static var huggingFaceHome: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface", isDirectory: true)
    }

    static func isModelCached(_ model: String = MakeFillable.model, in huggingFaceHome: URL = huggingFaceHome) -> Bool {
        let snapshots = huggingFaceHome.appendingPathComponent("hub/models--jbarrow--\(model)/snapshots", isDirectory: true)
        let revisions = (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? []
        return revisions.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("\(model).pt").path) }
    }

    static func hasAnnotations(_ document: PDFDocument) -> Bool {
        (0..<document.pageCount).contains { !(document.page(at: $0)?.annotations.isEmpty ?? true) }
    }

    static func fieldCount(_ document: PDFDocument) -> Int {
        (0..<document.pageCount).reduce(0) { count, index in
            count + (document.page(at: index)?.annotations.filter { $0.type == "Widget" }.count ?? 0)
        }
    }

    /// Whether any page has no text layer, so it's probably a scan. A locked
    /// PDF's text can't be read, so it doesn't count.
    static func hasScannedPages(_ document: PDFDocument) -> Bool {
        !document.isLocked && (0..<document.pageCount).contains { index in
            document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    /// Saves the fillable copy and returns it, or nil when no fields were found
    /// and nothing was saved.
    static func make(_ source: URL, tools: ExternalTools = .current, huggingFaceHome: URL = huggingFaceHome) async throws -> URL? {
        guard let executable = tools.commonforms else { throw MissingToolError(name: "commonforms") }
        guard let document = PDFDocument(url: source) else { throw PDFToolError.unreadable(source) }
        if document.isLocked { throw PDFToolError.locked(source) }
        if fieldCount(document) > 0 { throw ConversionError.failed("“\(source.lastPathComponent)” is already fillable.") }
        let base = source.deletingPathExtension().lastPathComponent + ".fillable"
        // Before the run, which can take minutes with the first-run download.
        try SaveError.checkWritable(OutputNaming.uniqueURL(in: source.deletingLastPathComponent(), baseName: base, pathExtension: "pdf"))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-fillable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A copy under a fixed name, so a file name can't pass for an option.
        let input = folder.appendingPathComponent("input.pdf")
        let output = folder.appendingPathComponent("output.pdf")
        try FileManager.default.copyItem(at: source, to: input)
        let keepingExisting = hasAnnotations(document)

        func findsFields(with model: String) async throws -> Bool {
            try? FileManager.default.removeItem(at: output)
            do {
                try await ProcessRunner.run(
                    executable, arguments(input: input, output: output, keepingExisting: keepingExisting, model: model),
                    currentDirectory: folder,
                    environment: environment(folder: folder, huggingFaceHome: huggingFaceHome, isModelCached: isModelCached(model, in: huggingFaceHome))
                )
            } catch let failure as ProcessFailure {
                throw ConversionError.failed("“\(source.lastPathComponent)” couldn’t be made fillable: \(FailureMessage.sanitized(failure.message))")
            }
            try Task.checkCancellation()
            return PDFDocument(url: output).map { fieldCount($0) > 0 } ?? false
        }

        var found = try await findsFields(with: model)
        if !found { found = try await findsFields(with: largeModel) }
        guard found else { return nil }
        let destination = OutputNaming.uniqueURL(in: source.deletingLastPathComponent(), baseName: base, pathExtension: "pdf")
        try await PartialFile.write(destination) { try FileManager.default.copyItem(at: output, to: $0) }
        return destination
    }
}
