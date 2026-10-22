import Foundation

/// Source files re-laid-out by a formatter, saved as "name.formatted.ext"
/// next to the original.
///
/// The files are untrusted, so a formatter only ever sees the file's text,
/// on standard input, never its path. It runs in an empty folder of its own
/// that is also its HOME, so no config next to the file, above it, or in the
/// home folder is found. Each one also gets an explicit config or style, so a
/// config left above the temporary folder can't apply either: on their own,
/// deno reads .editorconfig, swift-format .swift-format, and cljfmt and
/// rustfmt search parent folders.
enum PrettyPrint {
    enum Formatter: Equatable, Sendable {
        /// deno's --ext value.
        case deno(String)
        case cljfmt
        case ruff
        case shfmt
        case swiftFormat
        case xmllint
        case pgFormat
        /// A file name with the source's extension, which picks clang-format's language.
        case clangFormat(String)
        case gofmt
        case rustfmt
    }

    static let xmllint = URL(fileURLWithPath: "/usr/bin/xmllint")

    /// The formatter for files ending in `pathExtension`, or nil.
    static func formatter(forExtension pathExtension: String) -> Formatter? {
        let name = pathExtension.lowercased()
        switch name {
        case "js", "mjs", "cjs": return .deno("js")
        case "ts", "mts", "cts": return .deno("ts")
        case "jsx", "tsx", "json", "jsonc", "md", "css", "scss", "less", "html", "yaml": return .deno(name)
        case "markdown": return .deno("md")
        case "yml": return .deno("yaml")
        case "htm": return .deno("html")
        case "clj", "cljs", "cljc", "edn": return .cljfmt
        case "py", "pyi": return .ruff
        case "sh", "bash": return .shfmt
        case "swift": return .swiftFormat
        case "xml", "xsd", "xsl", "xslt": return .xmllint
        case "sql": return .pgFormat
        case "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm": return .clangFormat("source.\(name)")
        case "go": return .gofmt
        case "rs": return .rustfmt
        default: return nil
        }
    }

    /// The formatter for `url` when it's installed. A ".ts" that is really a
    /// video (an MPEG transport stream) has none.
    static func formatter(for url: URL, tools: ExternalTools) -> (formatter: Formatter, executable: URL)? {
        guard let formatter = formatter(forExtension: url.pathExtension), FileKind(url: url) != .video,
              let executable = executable(for: formatter, tools: tools.formatters) else { return nil }
        return (formatter, executable)
    }

    static func executable(for formatter: Formatter, tools: ExternalTools.Formatters) -> URL? {
        switch formatter {
        case .deno: tools.deno
        case .cljfmt: tools.cljfmt
        case .ruff: tools.ruff
        case .shfmt: tools.shfmt
        case .swiftFormat: tools.swiftFormat
        case .xmllint: FileManager.default.isExecutableFile(atPath: xmllint.path) ? xmllint : nil
        case .pgFormat: tools.pgFormat
        case .clangFormat: tools.clangFormat
        case .gofmt: tools.gofmt
        case .rustfmt: tools.rustfmt
        }
    }

    /// Each formatter reads standard input and writes standard output, with
    /// any config it would look for given explicitly. `folder` is the empty
    /// folder it runs in.
    static func arguments(for formatter: Formatter, folder: URL) -> [String] {
        switch formatter {
        case .deno(let ext):
            ["fmt", "--no-config", "--indent-width", "2", "--line-width", "80", "--use-tabs=false", "--ext", ext, "-"]
        case .cljfmt: ["fix", "--config", folder.appendingPathComponent("cljfmt.edn").path, "-"]
        case .ruff: ["format", "--isolated", "--stdin-filename", "source.py", "-"]
        case .shfmt: ["-i", "2", "-"]
        case .swiftFormat: ["format", "--configuration", #"{"version":1}"#, "-"]
        case .xmllint: ["--format", "--nonet", "-"]
        case .pgFormat: ["--no-rcfile", "-"]
        case .clangFormat(let name): ["--style=LLVM", "--assume-filename=\(name)"]
        case .gofmt: []
        case .rustfmt: ["--edition", "2024", "--config-path", folder.appendingPathComponent("rustfmt.toml").path]
        }
    }

    /// The empty configs the explicit-config arguments point at.
    static let configFiles = ["cljfmt.edn": "{}", "rustfmt.toml": ""]

    /// Saves a formatted copy of `source` and returns it, or nil when the
    /// file was already formatted and nothing was saved.
    static func format(_ source: URL, tools: ExternalTools = .current) async throws -> URL? {
        guard let (formatter, executable) = formatter(for: source, tools: tools) else {
            throw ConversionError.unsupported("pretty printing “\(source.lastPathComponent)”")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-format-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, contents) in configFiles {
            try contents.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let output = folder.appendingPathComponent("output")
        let environment = ChildEnvironment.minimal(extra: [
            "HOME": folder.path, "TMPDIR": folder.path, "XDG_CONFIG_HOME": folder.path,
            "DENO_NO_UPDATE_CHECK": "1", "NO_COLOR": "1",
        ])
        do {
            try await ProcessRunner.run(
                executable, arguments(for: formatter, folder: folder),
                currentDirectory: folder, environment: environment,
                standardInputFile: source, standardOutputFile: output
            )
        } catch let failure as ProcessFailure {
            throw explain(failure, source: source)
        }

        let formatted = try Data(contentsOf: output)
        let original = try Data(contentsOf: source)
        guard !formatted.isEmpty || original.isEmpty else {
            throw ConversionError.failed("“\(source.lastPathComponent)” couldn’t be formatted, so nothing was saved.")
        }
        if isSame(formatted, original) { return nil }
        let base = source.deletingPathExtension().lastPathComponent + ".formatted"
        let destination = OutputNaming.uniqueURL(in: source.deletingLastPathComponent(), baseName: base, pathExtension: source.pathExtension)
        try await PartialFile.write(destination) { try formatted.write(to: $0) }
        return destination
    }

    /// Whether two texts differ only in trailing blank lines, which pg_format adds.
    static func isSame(_ formatted: Data, _ original: Data) -> Bool {
        func trimmed(_ data: Data) -> Data {
            var data = data
            while let last = data.last, last == 0x0A || last == 0x0D || last == 0x20 { data.removeLast() }
            return data
        }
        return trimmed(formatted) == trimmed(original)
    }

    /// The formatter's first error line, which names the problem; its last is
    /// often a stack frame or a caret.
    static func explain(_ failure: ProcessFailure, source: URL) -> Error {
        let line = failure.errorOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return failure }
        return ConversionError.failed("“\(source.lastPathComponent)” couldn’t be formatted: \(FailureMessage.sanitized(line))")
    }
}
