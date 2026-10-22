import Foundation

/// Markup documents through pandoc: LaTeX, Typst, reStructuredText,
/// AsciiDoc and Org in and out, alongside Markdown, Word, HTML and EPUB.
enum PandocConversion {
    /// Files only pandoc reads properly.
    static let markupExtensions: Set<String> = ["tex", "latex", "adoc", "asciidoc", "rst", "org", "typ"]
    /// What only pandoc writes, in wheel order.
    static let markupFormats: [OutputFormat] = [.tex, .typ, .rst, .adoc, .org]
    /// What a markup file can become.
    static let formatsForMarkup: [OutputFormat] = [.docx, .md, .html, .epub, .txt] + markupFormats

    /// pandoc's reader for `url`, or nil when it has none.
    static func reader(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "txt", "text": "markdown"
        case "docx": "docx"
        case "odt": "odt"
        case "html", "htm": "html"
        case "rtf": "rtf"
        case "tex", "latex": "latex"
        case "adoc", "asciidoc": "asciidoc"
        case "rst": "rst"
        case "org": "org"
        case "typ": "typst"
        default: nil
        }
    }

    /// pandoc's writer for `format`, or nil when it has none OpenShelf uses.
    static func writer(for format: OutputFormat) -> String? {
        switch format {
        case .md: "markdown"
        case .docx: "docx"
        case .html: "html"
        case .epub: "epub"
        case .txt: "plain"
        case .tex: "latex"
        case .typ: "typst"
        case .rst: "rst"
        case .adoc: "asciidoc"
        case .org: "org"
        default: nil
        }
    }

    /// Whether pandoc does this conversion rather than OpenShelf's own code:
    /// whenever markup is read or written.
    static func handles(_ source: URL, to format: OutputFormat) -> Bool {
        guard reader(for: source) != nil, writer(for: format) != nil else { return false }
        return markupFormats.contains(format) || markupExtensions.contains(source.pathExtension.lowercased())
    }

    /// `--sandbox` keeps pandoc to the input and output files: no network,
    /// no other files (so images a document links to aren't pulled in).
    static func arguments(source: URL, to format: OutputFormat, output: URL) -> [String] {
        guard let reader = reader(for: source), let writer = writer(for: format) else { return [] }
        // Whole documents rather than fragments, where the format has both.
        let standalone: [String] = [.html, .tex, .typ].contains(format) ? ["--standalone"] : []
        return ["--sandbox", "--from", reader, "--to", writer] + standalone + ["--output", output.path, source.path]
    }

    static func convert(_ source: URL, to format: OutputFormat, tools: ExternalTools) async throws -> URL {
        guard let pandoc = tools.pandoc else { throw MissingToolError(name: "pandoc") }
        guard handles(source, to: format), let pathExtension = format.fileExtension else {
            throw ConversionError.unsupported("\(source.pathExtension.uppercased()) to \(format.title)")
        }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        try await PartialFile.write(destination) { partial in
            try await ProcessRunner.run(pandoc, arguments(source: source, to: format, output: partial))
        }
        return destination
    }
}
