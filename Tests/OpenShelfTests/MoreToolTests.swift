import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import OpenShelf

/// OCR, transcription helpers and the other non-media tools.
struct MoreToolTests {
    /// A fresh, empty folder.
    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Black `text` on white, large enough for Vision to read.
    static func picture(of text: String, size: CGSize = CGSize(width: 1200, height: 300)) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 60, y: 110)
        CTLineDraw(line, context)
        return try #require(context.makeImage())
    }

    // MARK: OCR

    @Test func picksSystemLanguagesVisionKnows() {
        let supported = ["en-US", "fr-FR", "de-DE", "zh-Hans"]
        #expect(OCR.recognitionLanguages(preferred: ["en-GB", "de-AT", "ja-JP"], supported: supported) == ["en-US", "de-DE"])
        #expect(OCR.recognitionLanguages(preferred: ["fr-FR", "fr-CA"], supported: supported) == ["fr-FR"])
    }

    @Test func readsTopToBottomThenLeftToRight() {
        let lines = [
            OCR.Line(text: "b", box: CGRect(x: 0.5, y: 0.8, width: 0.1, height: 0.05)),
            OCR.Line(text: "c", box: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.05)),
            OCR.Line(text: "a", box: CGRect(x: 0.1, y: 0.81, width: 0.1, height: 0.05)),
        ]
        #expect(OCR.readingOrder(lines).map(\.text) == ["a", "b", "c"])
    }

    @Test func recognisesTextInAnImageAndAScannedPDF() async throws {
        let folder = try workspace()
        let png = folder.appendingPathComponent("Scan.png")
        try EditableImage.write(try Self.picture(of: "Hello OpenShelf 2026"), to: png, type: .png)

        let text = try await OCR.run(png, output: .text)
        #expect(text.lastPathComponent == "Scan OCR.txt")
        #expect(try String(contentsOf: text, encoding: .utf8).contains("OpenShelf"))

        let pdf = try await OCR.run(png, output: .searchablePDF)
        #expect(pdf.lastPathComponent == "Scan OCR.pdf")
        let document = try #require(PDFDocument(url: pdf))
        #expect(document.string?.contains("OpenShelf") == true)
        // Found where it's drawn: the text sits across the middle of the page.
        let selection = try #require(document.findString("OpenShelf", withOptions: []).first)
        let bounds = selection.bounds(for: try #require(document.page(at: 0)))
        #expect(bounds.minY > 0 && bounds.maxY < 300 && bounds.width > 100)

        // That scan-only PDF, read again: its page now has text, so it's kept as it is.
        let again = try await OCR.run(pdf, output: .text)
        #expect(try String(contentsOf: again, encoding: .utf8).contains("OpenShelf"))
    }
}
