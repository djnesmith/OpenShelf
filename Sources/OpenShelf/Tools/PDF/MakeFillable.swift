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
    /// Not the CLI's default FFDNet-L: the small model found every field L did
    /// on typed forms, more on image-only pages, and downloads 18 MB, not 49.
    static let model = "FFDNet-S"
    static let modelDownloadNote = "Downloading the form model, 18 MB, first time only"
    static let scannedNote = "Scanned pages may miss most fields"
    /// commonforms finds the old fields' blanks again and adds a same-named field on each.
    static let existingFieldsNote = "This PDF already has form fields; the copy will repeat them"

    /// - Parameter keepingExisting: The PDF has annotations. commonforms
    ///   otherwise deletes every one, links and comments included.
    static func arguments(input: URL, output: URL, keepingExisting: Bool) -> [String] {
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

    static func isModelCached(in huggingFaceHome: URL = huggingFaceHome) -> Bool {
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

        do {
            try await ProcessRunner.run(
                executable, arguments(input: input, output: output, keepingExisting: hasAnnotations(document)),
                currentDirectory: folder,
                environment: environment(folder: folder, huggingFaceHome: huggingFaceHome, isModelCached: isModelCached(in: huggingFaceHome))
            )
        } catch let failure as ProcessFailure {
            throw ConversionError.failed("“\(source.lastPathComponent)” couldn’t be made fillable: \(FailureMessage.sanitized(failure.message))")
        }

        try Task.checkCancellation()
        guard let result = PDFDocument(url: output), fieldCount(result) > fieldCount(document) else { return nil }
        let destination = OutputNaming.uniqueURL(in: source.deletingLastPathComponent(), baseName: base, pathExtension: "pdf")
        try await PartialFile.write(destination) { try FileManager.default.copyItem(at: output, to: $0) }
        return destination
    }
}
