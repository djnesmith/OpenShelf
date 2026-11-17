import Foundation

/// The text wheel's tools that reuse OpenShelf's file converters: the text
/// goes into a temporary file, the converter runs on it, and the result is
/// read back. The temporary folder is removed afterwards.
enum TextConversion {
    /// One step of a data conversion.
    enum Hop: Equatable {
        /// Through `Converter` (yq for JSON, YAML and XML; jet for EDN).
        case converter(from: DataTextFormat, to: DataTextFormat)
        /// yq in place, for TOML, which isn't one of the file formats.
        case yq(from: DataTextFormat, to: DataTextFormat)
    }

    /// The steps from one format to another. Pairs no single tool handles
    /// (EDN and XML, anything and TOML) go through JSON.
    static func plan(from source: DataTextFormat, to target: DataTextFormat) -> [Hop] {
        guard source != target else { return [] }
        if let hop = direct(source, target) { return [hop] }
        return plan(from: source, to: .json) + plan(from: .json, to: target)
    }

    private static func direct(_ source: DataTextFormat, _ target: DataTextFormat) -> Hop? {
        let yqFiles: Set<DataTextFormat> = [.json, .yaml, .xml]
        switch (source, target) {
        case (.toml, .json), (.json, .toml), (.toml, .yaml), (.yaml, .toml):
            return .yq(from: source, to: target)
        case (.edn, .json), (.edn, .yaml), (.json, .edn), (.yaml, .edn):
            return .converter(from: source, to: target)
        case _ where yqFiles.contains(source) && yqFiles.contains(target):
            return .converter(from: source, to: target)
        default:
            return nil
        }
    }

    static func convert(
        _ text: String,
        from source: DataTextFormat,
        to target: DataTextFormat,
        tools: ExternalTools,
        runner: ToolRunner = ProcessRunner.live
    ) async throws -> String {
        try await withWorkspace { folder in
            var current = folder.appendingPathComponent("selection.\(source.fileExtension)")
            try text.write(to: current, atomically: true, encoding: .utf8)
            for hop in plan(from: source, to: target) {
                current = try await run(hop, on: current, tools: tools, runner: runner)
            }
            return try matchTrailingNewline(String(contentsOf: current, encoding: .utf8), of: text)
        }
    }

    private static func run(_ hop: Hop, on file: URL, tools: ExternalTools, runner: ToolRunner) async throws -> URL {
        switch hop {
        case .converter(_, let target):
            guard let format = OutputFormat(rawValue: target.rawValue),
                  let output = try await Converter.convert(file, to: format, tools: tools, progress: { _ in }).first else {
                throw ConversionError.unsupported("\(file.pathExtension.uppercased()) to \(target.title)")
            }
            return output
        case .yq(let source, let target):
            guard let yq = tools.yq else { throw MissingToolError(name: "yq") }
            let output = file.deletingLastPathComponent().appendingPathComponent("step-\(UUID().uuidString).\(target.fileExtension)")
            try FileManager.default.copyItem(at: file, to: output)
            try await runner(ToolInvocation(executable: yq, arguments: ["-p", source.rawValue, "-o", target.rawValue, "-i", output.path]), { _ in })
            return output
        }
    }

    /// Re-indents code with the formatter Pretty Print uses for `fileExtension`.
    /// Nil when the text was already formatted.
    static func reindent(_ text: String, fileExtension: String, tools: ExternalTools) async throws -> String? {
        if fileExtension == "json", PrettyPrint.formatter(forExtension: "json").flatMap({ PrettyPrint.executable(for: $0, tools: tools.formatters) }) == nil {
            return try prettyJSON(text)
        }
        return try await withWorkspace { folder in
            let file = folder.appendingPathComponent("selection.\(fileExtension)")
            try text.write(to: file, atomically: true, encoding: .utf8)
            guard let formatted = try await PrettyPrint.format(file, tools: tools) else { return nil }
            return try matchTrailingNewline(String(contentsOf: formatted, encoding: .utf8), of: text)
        }
    }

    /// JSON laid out by Foundation when deno isn't installed. Keys come out
    /// sorted, since Foundation doesn't keep their order.
    static func prettyJSON(_ text: String) throws -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        let result = String(decoding: pretty, as: UTF8.self)
        return matchTrailingNewline(result, of: text) == text ? nil : matchTrailingNewline(result, of: text)
    }

    /// The selection's HTML or RTF version as Markdown, through the same
    /// conversion a dropped .html or .rtf file gets.
    static func toMarkdown(_ rich: RichText, tools: ExternalTools) async throws -> String {
        try await withWorkspace { folder in
            let file = folder.appendingPathComponent("selection.\(rich.kind.fileExtension)")
            try rich.data.write(to: file)
            guard let output = try await Converter.convert(file, to: .md, tools: tools, progress: { _ in }).first else {
                throw ConversionError.unsupported("\(rich.kind.fileExtension.uppercased()) to Markdown")
            }
            return try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .newlines)
        }
    }

    /// Formatters and converters end files with a newline; a selection that
    /// didn't end with one shouldn't gain one, and one that did keeps it.
    static func matchTrailingNewline(_ result: String, of original: String) -> String {
        var trimmed = result
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        return original.hasSuffix("\n") ? trimmed + "\n" : trimmed
    }

    private static func withWorkspace<T>(_ body: (URL) async throws -> T) async throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await body(folder)
    }
}
