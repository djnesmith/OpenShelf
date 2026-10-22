import Foundation
import Testing
@testable import OpenShelf

/// Books through calibre, markup through pandoc, and data files through
/// Foundation and yq.
struct MoreConversionTests {
    static let ebookConvert = URL(fileURLWithPath: "/Applications/calibre.app/Contents/MacOS/ebook-convert")
    static var hasCalibre: Bool { FileManager.default.isExecutableFile(atPath: ebookConvert.path) }
    static let pandoc = URL(fileURLWithPath: "/opt/homebrew/bin/pandoc")
    static var hasPandoc: Bool { FileManager.default.isExecutableFile(atPath: pandoc.path) }

    let none = ExternalTools()
    let calibre = ExternalTools(ebookConvert: Self.ebookConvert)
    let pandoc = ExternalTools(pandoc: Self.pandoc)

    func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    /// A fresh, empty folder.
    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-conv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Ebooks

    @Test func booksAreBooks() {
        for name in ["a.epub", "a.mobi", "a.azw3", "a.azw", "a.fb2"] {
            #expect(FileKind(url: url(name)) == .ebook, "\(name)")
        }
    }

    @Test func booksConvertOnlyWithCalibre() {
        #expect(ConversionCatalog.formats(for: url("a.epub"), tools: none) == [.zip, .tar, .tgz])
        #expect(ConversionCatalog.formats(for: url("a.epub"), tools: calibre) == [.mobi, .azw3, .fb2, .pdf, .docx, .txt, .zip])
        #expect(ConversionCatalog.formats(for: url("a.mobi"), tools: calibre) == [.epub, .azw3, .fb2, .pdf, .docx, .txt, .zip])
        #expect(!ConversionCatalog.formats(for: url("a.pdf"), tools: none).contains(.mobi))
        #expect(ConversionCatalog.formats(for: url("a.pdf"), tools: calibre).suffix(4) == [.mobi, .azw3, .fb2, .zip])
    }

    @Test func readsCalibreProgress() {
        #expect(EbookConversion.fraction(fromProgressLine: "34% Running transforms on e-book") == 0.34)
        #expect(EbookConversion.fraction(fromProgressLine: "100% Creating MOBI Output") == 1)
        #expect(EbookConversion.fraction(fromProgressLine: "Converting input to HTML...") == nil)
        #expect(EbookConversion.fraction(fromProgressLine: "3 images") == nil)
    }

    @Test(.enabled(if: hasCalibre)) func convertsBooksBothWays() async throws {
        let folder = try workspace()
        let markdown = folder.appendingPathComponent("Book.md")
        try "# Chapter one\n\nIt was a dark and stormy night.\n".write(to: markdown, atomically: true, encoding: .utf8)
        let epub = try await DocumentConversion.convert(markdown, to: .epub)

        let mobi = try await EbookConversion.convert(epub, to: .mobi, tools: calibre) { _ in }
        #expect(mobi.lastPathComponent == "Book.mobi")
        let azw3 = try await EbookConversion.convert(epub, to: .azw3, tools: calibre) { _ in }
        #expect(azw3.lastPathComponent == "Book.azw3")
        let text = try await EbookConversion.convert(mobi, to: .txt, tools: calibre) { _ in }
        #expect(try String(contentsOf: text, encoding: .utf8).contains("dark and stormy night"))
        // Nothing half-written is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".openshelf-") })
    }

    // MARK: pandoc

    @Test func markupIsADocument() {
        for name in ["a.tex", "a.adoc", "a.asciidoc", "a.rst", "a.org", "a.typ"] {
            #expect(FileKind(url: url(name)) == .document, "\(name)")
        }
    }

    @Test func markupFormatsOnlyWithPandoc() {
        #expect(!ConversionCatalog.formats(for: url("a.md"), tools: none).contains(.tex))
        #expect(ConversionCatalog.formats(for: url("a.md"), tools: pandoc).suffix(6) == [.tex, .typ, .rst, .adoc, .org, .zip])
        #expect(ConversionCatalog.formats(for: url("a.rst"), tools: none) == [.zip])
        #expect(ConversionCatalog.formats(for: url("a.tex"), tools: none).first == .pdf)
        #expect(ConversionCatalog.formats(for: url("a.typ"), tools: pandoc) == [.docx, .md, .html, .epub, .txt, .tex, .rst, .adoc, .org, .zip])
        // Formats pandoc can't read get no markup outputs.
        #expect(!ConversionCatalog.formats(for: url("a.rtfd"), tools: pandoc).contains(.tex))
    }

    @Test func pandocRunsSandboxed() {
        let arguments = PandocConversion.arguments(source: url("a.md"), to: .tex, output: url("b.tex"))
        #expect(arguments == ["--sandbox", "--from", "markdown", "--to", "latex", "--standalone", "--output", "/tmp/b.tex", "/tmp/a.md"])
        #expect(PandocConversion.handles(url("a.rst"), to: .docx))
        #expect(!PandocConversion.handles(url("a.md"), to: .docx))
        #expect(!PandocConversion.handles(url("a.md"), to: .pdf))
    }

    @Test(.enabled(if: hasPandoc)) func convertsMarkupBothWays() async throws {
        let folder = try workspace()
        let markdown = folder.appendingPathComponent("Notes.md")
        try "# Title\n\nSome *emphasis* here.\n".write(to: markdown, atomically: true, encoding: .utf8)
        let expected: [(OutputFormat, String, String)] = [
            (.tex, "Notes.tex", "\\emph{emphasis}"),
            (.typ, "Notes.typ", "#emph[emphasis]"),
            (.rst, "Notes.rst", "*emphasis*"),
            (.adoc, "Notes.adoc", "_emphasis_"),
            (.org, "Notes.org", "/emphasis/"),
        ]
        for (format, name, snippet) in expected {
            let output = try await Converter.convert(markdown, to: format, tools: pandoc) { _ in }
            #expect(output.map(\.lastPathComponent) == [name])
            #expect(try String(contentsOf: output[0], encoding: .utf8).contains(snippet), "\(name)")
        }
        let rst = folder.appendingPathComponent("Notes.rst")
        let docx = try await Converter.convert(rst, to: .docx, tools: pandoc) { _ in }
        #expect(docx.map(\.lastPathComponent) == ["Notes.docx"])
        let back = try await Converter.convert(folder.appendingPathComponent("Notes.tex"), to: .md, tools: pandoc) { _ in }
        #expect(try String(contentsOf: back[0], encoding: .utf8).contains("*emphasis*"))
    }
}
