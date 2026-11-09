import Foundation
import Testing
@testable import OpenShelf

/// Runs the real qpdf on small PDFs written here.
struct CheckSafetyTests {
    static let tools = ExternalTools.detect()
    static var hasQPDF: Bool { tools.qpdf != nil }

    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-safety-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A one-page PDF with a correct xref. `catalog` is added to the catalog
    /// dictionary; `content` is the page's uncompressed content stream;
    /// `extra` are more objects, numbered from 5.
    func pdf(_ name: String, in folder: URL, catalog: String = "", content: String = "", extra: [String] = []) throws -> URL {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R \(catalog) >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        ] + extra
        var body = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(body.utf8.count)
            body += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = body.utf8.count
        body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        body += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        body += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = folder.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url
    }

    func check(_ url: URL) async throws -> CheckSafety.Result {
        try await CheckSafety.check(url, tools: Self.tools)
    }

    @Test(.enabled(if: hasQPDF)) func aPlainPDFIsSafe() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await check(try pdf("clean.pdf", in: folder, content: "BT /F1 12 Tf (Hello) Tj ET"))
        #expect(result.verdict == .safe)
        #expect(result.markers.isEmpty)
        #expect(result.reason == "no active content")
    }

    /// pdfid counts these bytes as JavaScript; they're page content, not keys.
    @Test(.enabled(if: hasQPDF)) func markerBytesInsideAStreamStaySafe() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await check(try pdf("bytes.pdf", in: folder, content: "% /JS /JavaScript /Launch /EmbeddedFile /OpenAction"))
        #expect(result.verdict == .safe)
    }

    @Test(.enabled(if: hasQPDF)) func anOpenActionWithoutJavaScriptIsWorthALook() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await check(try pdf("open.pdf", in: folder, catalog: "/OpenAction [3 0 R /Fit]"))
        #expect(result.verdict == .check)
        #expect(result.markers == ["/OpenAction": 1])
        #expect(result.reason == "real /OpenAction (usually fine, worth a look)")
    }

    @Test(.enabled(if: hasQPDF)) func javaScriptIsNotSafe() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await check(try pdf("js.pdf", in: folder, catalog: "/OpenAction << /S /JavaScript /JS (app.alert(1)) >>"))
        #expect(result.verdict == .notSafe)
        #expect(result.markers == ["/OpenAction": 1, "/JavaScript": 1, "/JS": 1])
        #expect(result.reason == "real /JS /JavaScript, runs on open via /OpenAction")
    }

    @Test(.enabled(if: hasQPDF)) func anEmbeddedFileIsNotSafe() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try pdf("embedded.pdf", in: folder, catalog: "/Names << /EmbeddedFiles << /Names [(a.txt) 5 0 R] >> >>", extra: [
            "<< /Type /Filespec /F (a.txt) /EF << /F 6 0 R >> >>",
            "<< /Type /EmbeddedFile /Length 2 >>\nstream\nhi\nendstream",
        ])
        let result = try await check(url)
        #expect(result.verdict == .notSafe)
        #expect(result.markers == ["/EmbeddedFiles": 1, "/EmbeddedFile": 1])
    }

    @Test(.enabled(if: hasQPDF)) func aFileQPDFCannotReadIsWorthALook() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: url)
        let result = try await check(url)
        #expect(result.verdict == .check)
        #expect(result.reason.hasPrefix("could not parse the file: "))
        #expect(!result.reason.contains(folder.path))
    }

    /// Nothing can show these bytes are only stream data, so they count.
    @Test(.enabled(if: hasQPDF)) func javaScriptBytesInAFileQPDFCannotReadAreNotSafe() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("js-broken.pdf")
        try Data("%PDF-1.7\n1 0 obj\n<< /Type /Catalog /OpenAction << /S /JavaScript /JS (app.alert(1)) >> >>\nendobj\n".utf8).write(to: url)
        let result = try await check(url)
        #expect(result.verdict == .notSafe)
        #expect(result.markers == ["/JS": 1, "/JavaScript": 1])
        #expect(result.reason.hasPrefix("qpdf could not parse; raw bytes contain /JS /JavaScript ("))
    }

    @Test func rawBytesCountOnlyWholeNames() {
        let counts = CheckSafety.rawDangerousNames(in: Data("/JSON /JS/XFA[/Launch] /RichMediaX /EmbeddedFiles".utf8))
        #expect(counts == ["/JS": 1, "/XFA": 1, "/Launch": 1, "/EmbeddedFiles": 1])
    }

    @Test(.enabled(if: hasQPDF)) func checkingNeverChangesThePDF() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try pdf("js.pdf", in: folder, catalog: "/OpenAction << /S /JavaScript /JS (app.alert(1)) >>")
        let before = try Data(contentsOf: url)
        _ = try await check(url)
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["js.pdf"])
    }

    @Test func severalFilesPutTheWorstOnTop() {
        func result(_ name: String, _ verdict: CheckSafety.Verdict, _ markers: [String: Int] = [:]) -> CheckSafety.Result {
            CheckSafety.Result(file: URL(fileURLWithPath: "/t/\(name)"), markers: markers, verdict: verdict, reason: "why")
        }
        let report = CheckSafety.report([
            result("a.pdf", .safe), result("b.pdf", .check, ["/ObjStm": 3]), result("c.pdf", .notSafe, ["/JS": 2, "/AA": 1]), result("d.pdf", .check),
        ])
        #expect(report == """
        c.pdf
          /AA  1
          /JS  2
        NOT SAFE: why

        b.pdf
          /ObjStm  3
        CHECK: why

        d.pdf
          no markers
        CHECK: why

        a.pdf
          no markers
        SAFE: why

        \(CheckSafety.caveat)
        """)
    }

    @Test func aQPDFWarningIsWorthALook() {
        let (verdict, reason) = CheckSafety.verdict(markers: [:], warning: "WARNING: a.pdf: file is damaged")
        #expect(verdict == .check)
        #expect(reason == "qpdf warning: WARNING: a.pdf: file is damaged")
    }

    @Test func theWedgeShowsOnlyWithQPDF() {
        let pdfs = [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf")]
        let qpdf = ExternalTools(ffmpeg: nil, cwebp: nil, qpdf: URL(fileURLWithPath: "/usr/bin/true"))
        #expect(FileTool.available(for: pdfs, tools: qpdf).contains(.checkSafety))
        #expect(FileTool.available(for: [pdfs[0]], tools: qpdf).contains(.checkSafety))
        #expect(!FileTool.available(for: pdfs, tools: ExternalTools()).contains(.checkSafety))
        #expect(CommandLineTool.qpdf.installCommand == "brew install qpdf")
    }
}
