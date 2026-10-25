import Foundation
import PDFKit
import Testing
@testable import OpenShelf

/// Books through calibre, markup through pandoc, and data files through
/// Foundation and yq.
struct MoreConversionTests {
    static let ebookConvert = URL(fileURLWithPath: "/Applications/calibre.app/Contents/MacOS/ebook-convert")
    static var hasCalibre: Bool { FileManager.default.isExecutableFile(atPath: ebookConvert.path) }
    static let pandoc = URL(fileURLWithPath: "/opt/homebrew/bin/pandoc")
    static var hasPandoc: Bool { FileManager.default.isExecutableFile(atPath: pandoc.path) }
    static let yq = URL(fileURLWithPath: "/opt/homebrew/bin/yq")
    static var hasYQ: Bool { FileManager.default.isExecutableFile(atPath: yq.path) }

    let none = ExternalTools()
    let calibre = ExternalTools(ebookConvert: Self.ebookConvert)
    let pandoc = ExternalTools(pandoc: Self.pandoc)
    let yq = ExternalTools(yq: Self.yq)

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
        #expect(ConversionCatalog.formats(for: url("a.epub"), tools: none) == ConversionCatalog.archiveFormats)
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

    @Test func calibreRunsWithoutTheGPU() {
        #expect(EbookConversion.environment(["HOME": "/Users/x", "GITHUB_TOKEN": "x"]) == [
            "HOME": "/Users/x", "PATH": ChildEnvironment.searchPath, "QTWEBENGINE_CHROMIUM_FLAGS": "--disable-gpu",
        ])
        #expect(EbookConversion.environment(["QTWEBENGINE_CHROMIUM_FLAGS": "--no-sandbox"])["QTWEBENGINE_CHROMIUM_FLAGS"] == "--no-sandbox --disable-gpu")
    }

    /// The conversion that crashed calibre's renderer when OpenShelf started it.
    @Test(.enabled(if: hasCalibre)) func convertsABookToPDF() async throws {
        let folder = try workspace()
        let markdown = folder.appendingPathComponent("Story.md")
        try "# One\n\nOnce upon a time.\n\n# Two\n\nThe end.\n".write(to: markdown, atomically: true, encoding: .utf8)
        let epub = try await DocumentConversion.convert(markdown, to: .epub)
        let pdf = try await EbookConversion.convert(epub, to: .pdf, tools: calibre) { _ in }
        #expect(pdf.lastPathComponent == "Story.pdf")
        let document = try #require(PDFDocument(url: pdf))
        #expect(document.string?.contains("Once upon a time") == true)
        // And back: a PDF into a book.
        try FileManager.default.removeItem(at: epub)
        let book = try await EbookConversion.convert(pdf, to: .epub, tools: calibre) { _ in }
        #expect(book.lastPathComponent == "Story.epub")
        let azw3 = try await EbookConversion.convert(book, to: .azw3, tools: calibre) { _ in }
        #expect(azw3.lastPathComponent == "Story.azw3")
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

    // MARK: Data files

    @Test func dataFormatsDependOnYQ() {
        for name in ["a.json", "a.yaml", "a.yml", "a.xml", "a.plist"] {
            #expect(FileKind(url: url(name)) == .data, "\(name)")
        }
        #expect(ConversionCatalog.formats(for: url("a.json"), tools: none) == [.plist, .zip])
        #expect(ConversionCatalog.formats(for: url("a.plist"), tools: none) == [.json, .zip])
        #expect(ConversionCatalog.formats(for: url("a.yml"), tools: none) == [.zip])
        #expect(ConversionCatalog.formats(for: url("a.yml"), tools: yq) == [.json, .xml, .plist, .csv, .zip])
        #expect(ConversionCatalog.formats(for: url("a.csv"), tools: yq).suffix(5) == [.json, .yaml, .xml, .sqlite, .zip])
    }

    @Test func xmlGetsOneRoot() {
        let wrapped = DataConversion.yqArguments(from: "json", to: .xml, source: url("a.json"))
        #expect(wrapped.contains(#"if (tag == "!!map" and length == 1) then . elif tag == "!!seq" then {"root": {"item": .}} else {"root": .} end"#))
        #expect(DataConversion.yqArguments(from: "yml", to: .json, source: url("a.yml")) == ["--input-format", "yaml", "--output-format", "json", ".", "/tmp/a.yml"])
    }

    @Test func jsonAndPropertyListsWithFoundation() async throws {
        let folder = try workspace()
        let json = folder.appendingPathComponent("Settings.json")
        try #"{"name": "OpenShelf", "sizes": [1, 2.5], "on": true}"#.write(to: json, atomically: true, encoding: .utf8)
        let plist = try await Converter.convert(json, to: .plist, tools: none) { _ in }
        #expect(plist.map(\.lastPathComponent) == ["Settings.plist"])
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist[0]), format: nil) as? [String: Any]
        #expect(object?["name"] as? String == "OpenShelf")

        try FileManager.default.removeItem(at: json)
        let back = try await Converter.convert(plist[0], to: .json, tools: none) { _ in }
        #expect(try String(contentsOf: back[0], encoding: .utf8).contains(#""name" : "OpenShelf""#))

        let nulls = folder.appendingPathComponent("Nulls.json")
        try #"{"a": null}"#.write(to: nulls, atomically: true, encoding: .utf8)
        await #expect(throws: (any Error).self) { try await Converter.convert(nulls, to: .plist, tools: none) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Nulls.plist").path))
    }

    @Test(.enabled(if: hasYQ)) func yamlXMLAndCSVWithYQ() async throws {
        let folder = try workspace()
        let yaml = folder.appendingPathComponent("People.yaml")
        try "- name: Ada\n  born: 1815\n- name: Grace\n  born: 1906\n".write(to: yaml, atomically: true, encoding: .utf8)
        let json = try await Converter.convert(yaml, to: .json, tools: yq) { _ in }
        #expect(try String(contentsOf: json[0], encoding: .utf8).contains(#""name": "Ada""#))
        let csv = try await Converter.convert(yaml, to: .csv, tools: yq) { _ in }
        #expect(try String(contentsOf: csv[0], encoding: .utf8).hasPrefix("name,born\nAda,1815"))
        let xml = try await Converter.convert(yaml, to: .xml, tools: yq) { _ in }
        let xmlText = try String(contentsOf: xml[0], encoding: .utf8)
        #expect(xmlText.hasPrefix("<root>\n  <item>") && xmlText.contains("<name>Grace</name>"))
        _ = try XMLDocument(contentsOf: xml[0])
        let plist = try await Converter.convert(yaml, to: .plist, tools: yq) { _ in }
        #expect(try PropertyListSerialization.propertyList(from: Data(contentsOf: plist[0]), format: nil) is [Any])

        // CSV and TSV tables become records.
        let table = folder.appendingPathComponent("Table.csv")
        try "a,b\n1,x\n".write(to: table, atomically: true, encoding: .utf8)
        let records = try await Converter.convert(table, to: .yaml, tools: yq) { _ in }
        #expect(try String(contentsOf: records[0], encoding: .utf8) == "- a: 1\n  b: x\n")
        // A property list through JSON to YAML.
        let fromPlist = try await Converter.convert(plist[0], to: .yaml, tools: yq) { _ in }
        #expect(try String(contentsOf: fromPlist[0], encoding: .utf8).contains("name: Ada"))
    }

    // MARK: More archives

    @Test func bsdtarWritesEachFormat() async throws {
        let folder = try workspace()
        let photos = folder.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try "hello".write(to: photos.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "".write(to: photos.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        let expected: [(OutputFormat, String, String)] = [(.txz, "Photos.tar.xz", "XZ"), (.tzst, "Photos.tar.zst", "Zstandard"), (.sevenZip, "Photos.7z", "7-zip")]
        for (format, name, magic) in expected {
            let archive = try await Converter.convert(photos, to: format, tools: none) { _ in }
            #expect(archive.map(\.lastPathComponent) == [name])
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/usr/bin/file")
            check.arguments = ["-b", archive[0].path]
            let pipe = Pipe()
            check.standardOutput = pipe
            try check.run()
            check.waitUntilExit()
            #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains(magic), "\(name)")

            // And back: the folder comes out without the Finder file.
            #expect(FileKind(url: archive[0]) == .archive)
            try FileManager.default.removeItem(at: photos)
            let extracted = try await Converter.convert(archive[0], to: .extract, tools: none) { _ in }
            #expect(try FileManager.default.contentsOfDirectory(atPath: extracted[0].path) == ["a.txt"], "\(name)")
            try FileManager.default.moveItem(at: extracted[0], to: photos)
            try "".write(to: photos.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        }
        #expect(OutputFormat.sevenZip.title == "7Z" && OutputFormat.sevenZip.fileExtension == "7z")
        #expect(FileKind(url: url("notes.txt.zst")) != .archive)
    }

    // MARK: More subtitles

    static let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    static var hasFFmpeg: Bool { FileManager.default.isExecutableFile(atPath: ffmpeg.path) }

    @Test func subtitleFormatsWithFFmpeg() {
        let withFFmpeg = ExternalTools(ffmpeg: Self.ffmpeg)
        #expect(FileKind(url: url("a.ass")) == .subtitle && FileKind(url: url("a.ssa")) == .subtitle)
        #expect(ConversionCatalog.formats(for: url("a.srt"), tools: none) == [.txt, .vtt, .zip])
        #expect(ConversionCatalog.formats(for: url("a.srt"), tools: withFFmpeg) == [.txt, .vtt, .ass, .ssa, .ttml, .zip])
        #expect(ConversionCatalog.formats(for: url("a.ass"), tools: none) == [.zip])
        #expect(ConversionCatalog.formats(for: url("a.ass"), tools: withFFmpeg) == [.srt, .vtt, .txt, .ssa, .ttml, .zip])
        #expect(SubtitleConversion.ffmpegArguments(url("a.srt"), to: .ttml) == ["-i", "/tmp/a.srt", "-map", "0:s:0", "-c:s", "ttml", "-f", "ttml"])
    }

    @Test(.enabled(if: hasFFmpeg)) func convertsSubtitlesThroughFFmpeg() async throws {
        let folder = try workspace()
        let srt = folder.appendingPathComponent("Film.srt")
        try "1\n00:00:01,000 --> 00:00:02,500\nHello there\n\n2\n00:00:03,000 --> 00:00:04,000\nGoodbye\n".write(to: srt, atomically: true, encoding: .utf8)
        let withFFmpeg = ExternalTools(ffmpeg: Self.ffmpeg)
        let ass = try await Converter.convert(srt, to: .ass, tools: withFFmpeg) { _ in }
        let assText = try String(contentsOf: ass[0], encoding: .utf8)
        #expect(ass.map(\.lastPathComponent) == ["Film.ass"] && assText.contains("[Events]") && assText.contains("Hello there"))
        let ttml = try await Converter.convert(srt, to: .ttml, tools: withFFmpeg) { _ in }
        #expect(try String(contentsOf: ttml[0], encoding: .utf8).contains("<tt"))
        _ = try XMLDocument(contentsOf: ttml[0])

        try FileManager.default.removeItem(at: srt)
        let back = try await Converter.convert(ass[0], to: .srt, tools: withFFmpeg) { _ in }
        #expect(try String(contentsOf: back[0], encoding: .utf8).contains("00:00:01,000 --> 00:00:02,500"))
        let text = try await Converter.convert(ass[0], to: .txt, tools: withFFmpeg) { _ in }
        #expect(try String(contentsOf: text[0], encoding: .utf8).contains("Goodbye"))
    }

    // MARK: JPEG XL

    static let cjxl = URL(fileURLWithPath: "/opt/homebrew/bin/cjxl")
    static var hasCJXL: Bool { FileManager.default.isExecutableFile(atPath: cjxl.path) }

    @Test func jpegXLOnlyWithCJXL() {
        #expect(!ConversionCatalog.formats(for: url("a.png"), tools: none).contains(.jxl))
        #expect(ConversionCatalog.formats(for: url("a.png"), tools: ExternalTools(cjxl: Self.cjxl)).contains(.jxl))
        #expect(FileKind(url: url("a.jxl")) == .image)
    }

    @Test(.enabled(if: hasCJXL)) func writesAndReadsJPEGXL() async throws {
        let folder = try workspace()
        let tools = ExternalTools(cjxl: Self.cjxl)
        let png = folder.appendingPathComponent("Shot.png")
        try EditableImage.write(try MoreToolTests.picture(of: "JXL"), to: png, type: .png)
        let jxl = try await Converter.convert(png, to: .jxl, tools: tools) { _ in }
        #expect(jxl.map(\.lastPathComponent) == ["Shot.jxl"])
        // ImageIO reads it back, so JPEG XL files convert to everything else with nothing installed.
        let image = try EditableImage.load(jxl[0])
        #expect(image.cgImage.width == 1200 && image.cgImage.height == 300)
        let back = try await Converter.convert(jxl[0], to: .jpg, tools: none) { _ in }
        #expect(back.map(\.lastPathComponent) == ["Shot.jpg"])

        // A JPEG is repacked losslessly: smaller than the JPEG.
        let fromJPEG = try await Converter.convert(back[0], to: .jxl, tools: tools) { _ in }
        let sizes = try [back[0], fromJPEG[0]].map { try #require(try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) }
        #expect(sizes[1] < sizes[0])
    }

    // MARK: Parquet and SQLite

    static let duckdb = URL(fileURLWithPath: "/opt/homebrew/bin/duckdb")
    static var hasDuckDB: Bool { FileManager.default.isExecutableFile(atPath: duckdb.path) }

    @Test func quotesNamesAndPaths() {
        #expect(DatabaseConversion.identifier(#"a "b"; DROP TABLE x"#) == #""a ""b""; DROP TABLE x""#)
        #expect(DatabaseConversion.literal("it's") == "'it''s'")
        let sql = DatabaseConversion.duckDBCopy(url("o'neil.parquet"), as: .csv, to: url("out.csv"))
        #expect(sql == "COPY (SELECT * FROM read_parquet('/tmp/o''neil.parquet')) TO '/tmp/out.csv' (FORMAT csv, HEADER true);")
        let arguments = DatabaseConversion.duckDBArguments("SELECT 1;")
        #expect(arguments.prefix(4) == ["-init", "/dev/null", "-batch", "-c"])
        #expect(arguments[4].hasPrefix("SET autoinstall_known_extensions = false;") && arguments[4].contains("lock_configuration = true"))
        let read = DatabaseConversion.sqliteReadArguments(url("a.db"), mode: ["-csv"], sql: "SELECT 1;")
        #expect(read == ["-readonly", "-safe", "-bail", "-init", "/dev/null", "-csv", "/tmp/a.db", "SELECT 1;"])
        #expect(DatabaseConversion.tableName(for: url("My Sales 2026.csv")) == "My_Sales_2026")
        #expect(DatabaseConversion.tableName(for: url("2026.csv")) == "t_2026")
    }

    @Test func databaseFormats() {
        let duck = ExternalTools(duckdb: Self.duckdb)
        #expect(FileKind(url: url("a.parquet")) == .data && FileKind(url: url("a.sqlite")) == .data)
        #expect(ConversionCatalog.formats(for: url("a.parquet"), tools: duck) == [.csv, .json, .xlsx, .zip])
        #expect(ConversionCatalog.formats(for: url("a.parquet"), tools: none) == [.zip])
        #expect(ConversionCatalog.formats(for: url("a.csv"), tools: duck).suffix(3) == [.parquet, .sqlite, .zip])
        #expect(ConversionCatalog.formats(for: url("a.csv"), tools: none).suffix(2) == [.sqlite, .zip])
        #expect(FileTool.available(for: [url("a.sqlite")], tools: none) == [.sqliteTables])
    }

    @Test(.enabled(if: hasDuckDB)) func parquetAndSQLiteRoundTrip() async throws {
        let folder = try workspace()
        let duck = ExternalTools(duckdb: Self.duckdb)
        let csv = folder.appendingPathComponent("People.csv")
        try "id,name\n1,Ada\n2,Grace\n".write(to: csv, atomically: true, encoding: .utf8)

        let parquet = try await Converter.convert(csv, to: .parquet, tools: duck) { _ in }
        #expect(parquet.map(\.lastPathComponent) == ["People.parquet"])
        #expect(try Data(contentsOf: parquet[0]).prefix(4) == Data("PAR1".utf8))
        try FileManager.default.removeItem(at: csv)
        let json = try await Converter.convert(parquet[0], to: .json, tools: duck) { _ in }
        #expect(try String(contentsOf: json[0], encoding: .utf8).contains(#""name":"Grace""#))
        let xlsx = try await Converter.convert(parquet[0], to: .xlsx, tools: duck) { _ in }
        #expect(try XlsxReader.firstSheet(of: xlsx[0]) == [["id", "name"], ["1", "Ada"], ["2", "Grace"]])
        let back = try await Converter.convert(parquet[0], to: .csv, tools: duck) { _ in }

        let database = try await Converter.convert(back[0], to: .sqlite, tools: none) { _ in }
        #expect(database.map(\.lastPathComponent) == ["People.sqlite"])
        #expect(FileSniffer.isSQLite(database[0]))
        #expect(try await DatabaseConversion.tables(in: database[0]) == ["People"])
        let exported = try await DatabaseConversion.export(tables: ["People"], from: database[0], as: .json)
        #expect(exported.map(\.lastPathComponent) == ["People People.json"])
        #expect(try String(contentsOf: exported[0], encoding: .utf8).contains(#""name":"Ada""#))
    }

    @Test func refusesToRunSQLFromTheFile() async throws {
        // A table named to break out of the query only ever reads that table.
        let folder = try workspace()
        let database = folder.appendingPathComponent("Trap.sqlite")
        let make = Process()
        make.executableURL = DatabaseConversion.sqlite3
        make.arguments = ["-init", "/dev/null", database.path, #"CREATE TABLE "x""; DROP TABLE keep; --" (a); CREATE TABLE keep (b); INSERT INTO keep VALUES (1);"#]
        try make.run()
        make.waitUntilExit()
        let tables = try await DatabaseConversion.tables(in: database)
        #expect(tables.contains("keep") && tables.count == 2)
        let saved = try await DatabaseConversion.export(tables: tables, from: database, as: .csv)
        #expect(saved.count == 2)
        #expect(try await DatabaseConversion.tables(in: database).contains("keep"))
    }

    // MARK: EDN

    static let jet = URL(fileURLWithPath: "/opt/homebrew/bin/jet")
    static var hasJet: Bool { FileManager.default.isExecutableFile(atPath: jet.path) }

    @Test func ednFormatsOnlyWithJet() {
        #expect(FileKind(url: url("a.edn")) == .data)
        #expect(ConversionCatalog.formats(for: url("a.edn"), tools: none) == [.zip])
        #expect(ConversionCatalog.formats(for: url("a.edn"), tools: ExternalTools(yq: Self.yq, jet: Self.jet)) == [.json, .yaml, .zip])
        #expect(ConversionCatalog.formats(for: url("a.json"), tools: ExternalTools(jet: Self.jet)).contains(.edn))
        #expect(EdnConversion.arguments(from: "json", to: "edn") == ["--from", "json", "--to", "edn", "--keywordize", EdnConversion.keywordizeValidKeys])
        #expect(EdnConversion.arguments(from: "edn", to: "json") == ["--from", "edn", "--to", "json"])
    }

    @Test(.enabled(if: hasJet && hasYQ)) func ednRoundTrips() async throws {
        let folder = try workspace()
        let tools = ExternalTools(yq: Self.yq, jet: Self.jet)
        let edn = folder.appendingPathComponent("Config.edn")
        try #"{:name "OpenShelf", :sizes [1 2.5 -3], :nested {:on true, :off nil}, :tags #{:a}, :sym hello}"#.write(to: edn, atomically: true, encoding: .utf8)

        let json = try await Converter.convert(edn, to: .json, tools: tools) { _ in }
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: json[0]), options: [.fragmentsAllowed]) as? [String: Any])
        #expect(object["name"] as? String == "OpenShelf")
        #expect(object["sizes"] as? [Double] == [1, 2.5, -3])
        #expect((object["nested"] as? [String: Any])?["off"] is NSNull)
        #expect(object["tags"] as? [String] == ["a"])
        #expect(object["sym"] as? String == "hello")

        // And back: keys become keywords again, nil stays nil.
        try FileManager.default.removeItem(at: edn)
        let back = try await Converter.convert(json[0], to: .edn, tools: tools) { _ in }
        let text = try String(contentsOf: back[0], encoding: .utf8)
        #expect(text.contains(#":name "OpenShelf""#) && text.contains(":off nil") && text.contains("[1 2.5 -3]"))

        // A key that isn't a valid keyword stays a string, so it reads back the same.
        let odd = folder.appendingPathComponent("Odd.json")
        try #"{"weird key": 1, "ok": 2}"#.write(to: odd, atomically: true, encoding: .utf8)
        let oddEdn = try String(contentsOf: try await Converter.convert(odd, to: .edn, tools: tools) { _ in }[0], encoding: .utf8)
        #expect(oddEdn.contains(#""weird key" 1"#) && oddEdn.contains(":ok 2"))

        let yaml = try await Converter.convert(back[0], to: .yaml, tools: tools) { _ in }
        #expect(try String(contentsOf: yaml[0], encoding: .utf8).contains("name: OpenShelf"))
    }

    @Test(.enabled(if: hasJet)) func refusesTaggedValuesJSONCantHold() async throws {
        let folder = try workspace()
        let edn = folder.appendingPathComponent("Tagged.edn")
        try #"{:x #my/tag [1 2]}"#.write(to: edn, atomically: true, encoding: .utf8)
        do {
            _ = try await Converter.convert(edn, to: .json, tools: ExternalTools(jet: Self.jet)) { _ in }
            Issue.record("A tagged literal was turned into JSON")
        } catch {
            #expect(error.localizedDescription.contains("tagged value"), "\(error.localizedDescription)")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Tagged.edn"])
    }

    // MARK: Excel's row limit

    func expectRefusal(_ folder: URL, _ body: () async throws -> Void) async {
        let before = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        do {
            try await body()
            Issue.record("a table over the limit was written")
        } catch {
            #expect(error.localizedDescription.hasPrefix("Excel holds up to"), "\(error.localizedDescription)")
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) == before, "something was saved")
    }

    @Test(.enabled(if: hasDuckDB)) func parquetAndSQLiteOverTheLimitAreRefused() async throws {
        let folder = try workspace()
        let duck = ExternalTools(duckdb: Self.duckdb)
        let csv = folder.appendingPathComponent("People.csv")
        try "id,name\n1,Ada\n2,Grace\n".write(to: csv, atomically: true, encoding: .utf8)
        let parquet = try await Converter.convert(csv, to: .parquet, tools: duck) { _ in }[0]
        let database = try await Converter.convert(csv, to: .sqlite, tools: none) { _ in }[0]
        try FileManager.default.removeItem(at: csv)
        #expect(try await DatabaseConversion.parquetRowCount(parquet, tools: duck) == 2)
        #expect(try await DatabaseConversion.rowCount(of: "People", in: database) == 2)

        // Two rows and the header: three.
        await expectRefusal(folder) { _ = try await DatabaseConversion.convert(parquet, to: .xlsx, tools: duck, rowLimit: 2) }
        await expectRefusal(folder) { _ = try await DatabaseConversion.export(tables: ["People"], from: database, as: .xlsx, rowLimit: 2) }
        #expect(try await DatabaseConversion.convert(parquet, to: .xlsx, tools: duck, rowLimit: 3).count == 1)
        #expect(try await DatabaseConversion.export(tables: ["People"], from: database, as: .xlsx, rowLimit: 3).count == 1)
    }
}
