import Foundation
import Testing
@testable import OpenShelf

/// Books through calibre, markup through pandoc, and data files through
/// Foundation and yq.
struct MoreConversionTests {
    static let ebookConvert = URL(fileURLWithPath: "/Applications/calibre.app/Contents/MacOS/ebook-convert")
    static var hasCalibre: Bool { FileManager.default.isExecutableFile(atPath: ebookConvert.path) }

    let none = ExternalTools()
    let calibre = ExternalTools(ebookConvert: Self.ebookConvert)

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
}
