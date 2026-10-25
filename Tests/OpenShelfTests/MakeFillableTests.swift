import AppKit
import Foundation
import PDFKit
import Testing
@testable import OpenShelf

/// Serialized: two PDFDocument writes at once fail now and then.
@Suite(.serialized)
struct MakeFillableTests {
    let commonforms = ExternalTools(ffmpeg: nil, cwebp: nil, commonforms: URL(fileURLWithPath: "/usr/bin/true"))

    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-fillable-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A one-page PDF with four form lines drawn as text, or an image when `scanned`.
    func formPDF(named name: String, in folder: URL, scanned: Bool = false) throws -> URL {
        let url = folder.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        if scanned {
            let pixels = try #require(CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            pixels.setFillColor(gray: 0.5, alpha: 1)
            pixels.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            context.draw(try #require(pixels.makeImage()), in: box)
        } else {
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (index, label) in ["Name", "Address", "Email", "Phone"].enumerated() {
                ("\(label): ________________________________________" as NSString)
                    .draw(at: CGPoint(x: 72, y: 700 - index * 40), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            }
            NSGraphicsContext.current = nil
        }
        context.endPDFPage()
        context.closePDF()
        return url
    }

    func addLink(to url: URL) throws {
        let document = try #require(PDFDocument(url: url))
        let link = PDFAnnotation(bounds: CGRect(x: 72, y: 72, width: 100, height: 20), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com")
        document.page(at: 0)?.addAnnotation(link)
        #expect(document.write(to: url))
    }

    @Test func runsTheSmallModelWithSignatureFields() {
        let arguments = MakeFillable.arguments(input: URL(fileURLWithPath: "/t/input.pdf"), output: URL(fileURLWithPath: "/t/output.pdf"), keepingExisting: false)
        #expect(arguments == ["/t/input.pdf", "/t/output.pdf", "--model", "FFDNet-S", "--use-signature-fields"])
    }

    /// commonforms deletes every annotation unless told to keep them.
    @Test func keepsExistingAnnotationsWhenThereAreAny() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = try formPDF(named: "plain.pdf", in: folder)
        let linked = try formPDF(named: "linked.pdf", in: folder)
        try addLink(to: linked)

        #expect(!MakeFillable.hasAnnotations(try #require(PDFDocument(url: plain))))
        #expect(MakeFillable.hasAnnotations(try #require(PDFDocument(url: linked))))
        #expect(MakeFillable.arguments(input: plain, output: plain, keepingExisting: true).last == "--keep-existing-fields")
    }

    @Test func staysOfflineOnceTheModelIsCached() {
        let folder = URL(fileURLWithPath: "/t/run")
        let cache = URL(fileURLWithPath: "/t/hf")
        let offline = MakeFillable.environment(folder: folder, huggingFaceHome: cache, isModelCached: true)
        #expect(offline["HOME"] == "/t/run")
        #expect(offline["YOLO_OFFLINE"] == "true")
        #expect(offline["YOLO_AUTOINSTALL"] == "0")
        #expect(offline["YOLO_CONFIG_DIR"] == "/t/run")
        #expect(offline["HF_HOME"] == "/t/hf")
        #expect(offline["HF_HUB_OFFLINE"] == "1")
        #expect(offline["HF_HUB_DISABLE_IMPLICIT_TOKEN"] == "1")
        #expect(offline["PATH"] == ChildEnvironment.searchPath)

        let downloading = MakeFillable.environment(folder: folder, huggingFaceHome: cache, isModelCached: false)
        #expect(downloading["HF_HUB_OFFLINE"] == nil)
        #expect(downloading["YOLO_OFFLINE"] == "true")
    }

    @Test func findsTheModelInTheHuggingFaceCache() throws {
        let cache = try workspace()
        defer { try? FileManager.default.removeItem(at: cache) }
        #expect(!MakeFillable.isModelCached(in: cache))
        let snapshot = cache.appendingPathComponent("hub/models--jbarrow--FFDNet-S/snapshots/abc123", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        #expect(!MakeFillable.isModelCached(in: cache))
        FileManager.default.createFile(atPath: snapshot.appendingPathComponent("FFDNet-S.pt").path, contents: Data([0]))
        #expect(MakeFillable.isModelCached(in: cache))
    }

    @Test func aPageWithoutTextCountsAsScanned() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!MakeFillable.hasScannedPages(try #require(PDFDocument(url: try formPDF(named: "text.pdf", in: folder)))))
        #expect(MakeFillable.hasScannedPages(try #require(PDFDocument(url: try formPDF(named: "scan.pdf", in: folder, scanned: true)))))
        #expect(!MakeFillable.hasScannedPages(try #require(PDFDocument(url: try lockedPDF(in: folder)))))
    }

    func lockedPDF(in folder: URL) throws -> URL {
        let url = try formPDF(named: "locked.pdf", in: folder)
        let document = try #require(PDFDocument(url: url))
        #expect(document.write(to: url, withOptions: [.userPasswordOption: "pw", .ownerPasswordOption: "pw"]))
        return url
    }

    func addField(to url: URL) throws {
        let document = try #require(PDFDocument(url: url))
        let field = PDFAnnotation(bounds: CGRect(x: 120, y: 695, width: 200, height: 20), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "name"
        document.page(at: 0)?.addAnnotation(field)
        #expect(document.write(to: url))
    }

    /// A stand-in commonforms that notes its arguments, then writes a PDF with
    /// one field, or copies the input when it `findsFields` is false.
    func stub(in folder: URL, exitCode: Int = 0, seconds: Int = 0, findsFields: Bool = true) throws -> (tools: ExternalTools, arguments: URL) {
        let arguments = folder.appendingPathComponent("arguments.txt")
        let script = folder.appendingPathComponent("commonforms")
        let found = try formPDF(named: "found-\(UUID().uuidString).pdf", in: folder)
        try addField(to: found)
        let result = findsFields ? "'\(found.path)'" : "\"$1\""
        try "#!/bin/sh\necho \"$@\" > '\(arguments.path)'\nsleep \(seconds)\ncp \(result) \"$2\"\nexit \(exitCode)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (ExternalTools(ffmpeg: nil, cwebp: nil, commonforms: script), arguments)
    }

    @Test func passesKeepFieldsForALinkAndSavesNextToTheOriginal() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (tools, arguments) = try stub(in: folder)
        let plain = try formPDF(named: "plain.pdf", in: folder)
        let linked = try formPDF(named: "linked.pdf", in: folder)
        try addLink(to: linked)

        #expect(try await MakeFillable.make(plain, tools: tools)?.lastPathComponent == "plain.fillable.pdf")
        #expect(try !String(contentsOf: arguments, encoding: .utf8).contains("--keep-existing-fields"))
        #expect(try await MakeFillable.make(linked, tools: tools)?.lastPathComponent == "linked.fillable.pdf")
        #expect(try String(contentsOf: arguments, encoding: .utf8).hasSuffix("--model FFDNet-S --use-signature-fields --keep-existing-fields\n"))
        #expect(try await MakeFillable.make(linked, tools: tools)?.lastPathComponent == "linked.fillable 2.pdf")
    }

    /// What closing the window does: the tool stops and nothing is saved.
    @Test func cancellingSavesNothing() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        let tools = try stub(in: folder, seconds: 5).tools
        let start = Date()
        let run = Task { try await MakeFillable.make(source, tools: tools) }
        try await Task.sleep(for: .milliseconds(500))
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        // The stub sleeps 5 s, so returning sooner means it was stopped, not waited for.
        #expect(Date().timeIntervalSince(start) < 4)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains(".fillable") })
    }

    @Test func noFieldsFoundSavesNothing() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        #expect(try await MakeFillable.make(source, tools: try stub(in: folder, findsFields: false).tools) == nil)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains(".fillable") })
        let outcome = SaveOutcome(saved: [], unchanged: 1, unchangedLabel: "no fields found")
        #expect(outcome.subtitle == "No fields found")
    }

    /// commonforms would stack a duplicate on each old field, so it never runs.
    @Test func refusesAPDFThatIsAlreadyFillable() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        try addField(to: source)
        let (tools, arguments) = try stub(in: folder)
        await #expect(throws: ConversionError.self) { try await MakeFillable.make(source, tools: tools) }
        #expect(!FileManager.default.fileExists(atPath: arguments.path))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains(".fillable") })
    }

    /// Links aren't fields, so a PDF with only links isn't refused.
    @Test func countsExistingFields() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        #expect(MakeFillable.fieldCount(try #require(PDFDocument(url: source))) == 0)
        try addLink(to: source)
        #expect(MakeFillable.fieldCount(try #require(PDFDocument(url: source))) == 0)
        try addField(to: source)
        #expect(MakeFillable.fieldCount(try #require(PDFDocument(url: source))) == 1)
    }

    @Test func aFailedRunSavesNothing() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        await #expect(throws: ConversionError.self) { try await MakeFillable.make(source, tools: try stub(in: folder, exitCode: 1).tools) }
        await #expect(throws: MissingToolError.self) { try await MakeFillable.make(source, tools: ExternalTools()) }
        let locked = try lockedPDF(in: folder)
        await #expect(throws: PDFToolError.self) { try await MakeFillable.make(locked, tools: try stub(in: folder).tools) }
        #expect(try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains(".fillable") })
    }

    @Test func offeredForOnePDFWhenCommonformsIsInstalled() {
        let pdf = URL(fileURLWithPath: "/tmp/a.pdf")
        #expect(FileTool.available(for: [pdf], tools: commonforms).last == .makeFillable)
        #expect(!FileTool.available(for: [pdf], tools: ExternalTools()).contains(.makeFillable))
        #expect(!FileTool.available(for: [pdf, URL(fileURLWithPath: "/tmp/b.pdf")], tools: commonforms).contains(.makeFillable))
    }

    /// Where `uv tool install` puts it, which no GUI app's PATH includes.
    @Test func foundWhereUvInstallsIt() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stub = folder.appendingPathComponent("commonforms")
        FileManager.default.createFile(atPath: stub.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let locations = ToolLocations(commandDirectories: [], libreOfficeApps: [], commonforms: [stub])
        #expect(ExternalTools.detect(in: locations, ignoring: []).commonforms == stub)
        #expect(ToolLocations.standard.commonforms.map(\.path).contains { $0.hasSuffix("/.local/share/uv/tools/commonforms/bin/commonforms") })
    }

    static var isInstalled: Bool { ExternalTools.current.commonforms != nil && MakeFillable.isModelCached() }

    /// The real tool: a link on the page survives, and the copy lands next to the original.
    @Test(.enabled(if: isInstalled)) func keepsALinkAndSavesNextToTheOriginal() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try formPDF(named: "form.pdf", in: folder)
        try addLink(to: source)

        let saved = try #require(try await MakeFillable.make(source))
        #expect(saved.lastPathComponent == "form.fillable.pdf")
        let page = try #require(PDFDocument(url: saved)?.page(at: 0))
        #expect(page.annotations.contains { $0.url == URL(string: "https://example.com") })
    }
}
