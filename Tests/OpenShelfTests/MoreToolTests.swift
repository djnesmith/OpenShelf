import AppKit
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
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

    // MARK: Transcription (the recogniser itself needs permission, so only the writing is tested)

    typealias Segment = Transcription.Segment

    @Test func splitsLongAudioIntoPieces() {
        #expect(Transcription.chunkStarts(duration: 0).isEmpty)
        #expect(Transcription.chunkStarts(duration: 30) == [0])
        #expect(Transcription.chunkStarts(duration: 120) == [0, 50, 100])
    }

    @Test func groupsWordsIntoSubtitles() {
        let words: [Segment] = [
            Segment(text: "Hello", start: 0, duration: 0.4),
            Segment(text: "there.", start: 0.5, duration: 0.4),
            Segment(text: "How", start: 1, duration: 0.3),
            Segment(text: "are", start: 1.4, duration: 0.2),
            Segment(text: "you", start: 1.7, duration: 0.3),
            Segment(text: "Later", start: 5, duration: 0.5),
        ]
        let cues = Transcription.cues(words)
        #expect(cues.map(\.text) == ["Hello there.", "How are you", "Later"])
        #expect(cues[1].start == 1 && abs(cues[1].end - 2) < 0.0001)
        #expect(Transcription.plainText(words) == "Hello there. How are you\n\nLater\n")
    }

    @Test func writesSRT() {
        #expect(Transcription.srtTime(3723.45) == "01:02:03,450")
        let srt = Transcription.srt([Segment(text: "Hi", start: 0, duration: 1.5), Segment(text: "Bye", start: 2, duration: 1)])
        #expect(srt == "1\n00:00:00,000 --> 00:00:01,500\nHi\n\n2\n00:00:02,000 --> 00:00:03,000\nBye\n")
    }

    @Test func tellsWhyNothingWasSent() {
        #expect(TranscriptionError.notOnDevice("English").localizedDescription.contains("nothing was sent"))
    }

    // MARK: PDF pages as images

    @Test func selectsPages() {
        #expect(PDFTools.selectedPages("", pageCount: 3) == .success([0, 1, 2]))
        #expect(PDFTools.selectedPages("3, 1-2, 2", pageCount: 5) == .success([0, 1, 2]))
        #expect(PDFTools.selectedPages("4-", pageCount: 5) == .success([3, 4]))
        guard case .failure = PDFTools.selectedPages("9", pageCount: 5) else { Issue.record("page 9 of 5 accepted"); return }
    }

    @Test func savesChosenPagesAtTheResolution() async throws {
        let folder = try workspace()
        // Three A4-ish pages (595×842 pt) from three pictures.
        let document = PDFDocument()
        for number in 1...3 {
            let page = try #require(PDFPage(image: NSImage(cgImage: try Self.picture(of: "Page \(number)"), size: NSSize(width: 595, height: 842))))
            document.insert(page, at: document.pageCount)
        }
        let pdf = folder.appendingPathComponent("Doc.pdf")
        #expect(document.write(to: pdf))
        let outputs = try await PDFTools.exportImages(of: pdf, pages: [0, 2], as: .png, dpi: 144)
        #expect(outputs.map(\.lastPathComponent) == ["Doc Page 1.png", "Doc Page 3.png"])
        let image = try EditableImage.load(outputs[0]).cgImage
        #expect(image.width == 1190 && image.height == 1684)
    }

    // MARK: Smart crop

    @Test func cropsAroundTheSubject() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let subject = CGRect(x: 700, y: 200, width: 100, height: 100)
        // Free: the subject with a tenth around it.
        #expect(SmartCrop.crop(around: subject, ratio: nil, in: bounds) == CGRect(x: 690, y: 190, width: 120, height: 120))
        // 16:9 widens around it.
        let wide = SmartCrop.crop(around: subject, ratio: 16 / 9, in: bounds)
        #expect(wide.contains(subject) && abs(wide.width / wide.height - 16 / 9) < 0.02)
        // Too big a ratio for the bounds: the largest that fits, kept over the subject.
        let tall = SmartCrop.crop(around: CGRect(x: 900, y: 0, width: 100, height: 500), ratio: 9 / 16, in: bounds)
        #expect(tall.height == 500 && tall.maxX == 1000)
    }

    @Test func visionFindsTheSubject() throws {
        // A dark blob on the right of a plain light picture.
        let size = CGSize(width: 800, height: 400)
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 560, y: 120, width: 160, height: 160))
        let picture = try #require(context.makeImage())
        let subject = try #require(try SmartCrop.subject(in: picture))
        #expect(subject.midX > 400)
    }

    // MARK: GIF loop

    @Test func gifsGetALoopTool() {
        #expect(FileTool.available(for: [URL(fileURLWithPath: "/tmp/a.gif")], tools: ExternalTools()).contains(.gifLoop))
        #expect(!FileTool.available(for: [URL(fileURLWithPath: "/tmp/a.png")], tools: ExternalTools()).contains(.gifLoop))
    }

    @Test func setsHowManyTimesAGIFPlays() throws {
        let folder = try workspace()
        let gif = folder.appendingPathComponent("Anim.gif")
        let destination = try #require(CGImageDestinationCreateWithURL(gif as CFURL, "com.compuserve.gif" as CFString, 3, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for text in ["1", "2", "3"] {
            CGImageDestinationAddImage(destination, try Self.picture(of: text, size: CGSize(width: 200, height: 200)),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        #expect(GIFLoop.loopCount(of: gif) == 0)

        let thrice = try GIFLoop.save(gif, plays: .threeTimes)
        #expect(thrice.lastPathComponent == "Anim Plays 3×.gif")
        #expect(GIFLoop.loopCount(of: thrice) == 3)
        // In the file, the GIF's own repeat count: two more after the first play.
        let data = try Data(contentsOf: thrice)
        let netscape = try #require(data.range(of: Data("NETSCAPE2.0".utf8)))
        #expect(Array(data[netscape.upperBound..<netscape.upperBound + 4]) == [3, 1, 2, 0])
        let source = try #require(CGImageSourceCreateWithURL(thrice as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        let frame = CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any]
        let delay = (frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFDelayTime] as? Double
        #expect(delay == 0.25)

        let once = try GIFLoop.save(gif, plays: .once)
        #expect(GIFLoop.loopCount(of: once) == 1)
        #expect(try Data(contentsOf: once).range(of: Data("NETSCAPE2.0".utf8)) == nil)
    }

    // MARK: Icons and animated PNG

    @Test func makesIconsWithEverySize() async throws {
        let folder = try workspace()
        let png = folder.appendingPathComponent("Logo.png")
        try EditableImage.write(try Self.picture(of: "OS", size: CGSize(width: 600, height: 400)), to: png, type: .png)
        let outputs = try await IconMaker.make(png)
        #expect(outputs.map(\.lastPathComponent) == ["Logo.icns", "Logo.ico"])
        // iconutil lists the icns's members; 64 and 1024 are the @2x of 32 and 512.
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        let set = folder.appendingPathComponent("Check.iconset")
        listing.arguments = ["-c", "iconset", outputs[0].path, "-o", set.path]
        try listing.run()
        listing.waitUntilExit()
        let names = try FileManager.default.contentsOfDirectory(atPath: set.path)
        #expect(Set(names) == Set(IconMaker.iconsetEntries.map { "icon_\($0.points)x\($0.points)\($0.scale == 2 ? "@2x" : "").png" }))
        let ico = try #require(CGImageSourceCreateWithURL(outputs[1] as CFURL, nil))
        let widths = (0..<CGImageSourceGetCount(ico)).compactMap { CGImageSourceCreateImageAtIndex(ico, $0, nil)?.width }
        #expect(Set(widths) == Set(IconMaker.icoSizes), "\(widths)")
        // Wide pictures are fitted, not stretched: the corners stay clear.
        let square = try #require(IconMaker.square(try Self.picture(of: "", size: CGSize(width: 400, height: 200)), side: 64))
        #expect(square.width == 64 && square.height == 64)
    }

    @Test func turnsAGIFIntoAnAnimatedPNG() async throws {
        let folder = try workspace()
        let gif = folder.appendingPathComponent("Anim.gif")
        let destination = try #require(CGImageDestinationCreateWithURL(gif as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        for text in ["A", "B"] {
            CGImageDestinationAddImage(destination, try Self.picture(of: text, size: CGSize(width: 120, height: 120)),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        #expect(ConversionCatalog.formats(for: gif, tools: ExternalTools()).contains(.apng))
        #expect(!ConversionCatalog.formats(for: folder.appendingPathComponent("a.jpg"), tools: ExternalTools()).contains(.apng))

        let output = try await Converter.convert(gif, to: .apng, tools: ExternalTools()) { _ in }
        #expect(output.map(\.lastPathComponent) == ["Anim.png"])
        let source = try #require(CGImageSourceCreateWithURL(output[0] as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        let frame = CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any]
        let png = frame?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(png?[kCGImagePropertyAPNGDelayTime] as? Double == 0.5)
    }

    // MARK: Terminal app

    @Test func prefersITermThenTerminal() {
        let iTerm = URL(fileURLWithPath: "/Applications/iTerm.app"), terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let both: [String: URL] = [TerminalApp.iTermIdentifier: iTerm, TerminalApp.terminalIdentifier: terminal]
        #expect(TerminalApp.choose { both[$0] }.map { [$0.url.path, $0.name] } == [iTerm.path, "iTerm"])
        #expect(TerminalApp.choose { $0 == TerminalApp.terminalIdentifier ? terminal : nil }.map { [$0.url.path, $0.name] } == [terminal.path, "Terminal"])
        #expect(TerminalApp.choose { _ in nil } == nil)
        #expect(FileAction.terminal.title == TerminalApp.name)
    }

    // MARK: Copy Name

    /// On a private pasteboard, so the test never touches the real clipboard.
    @MainActor
    @Test func copiesNamesInCopyPathsOrder() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("openshelf-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        FileActions.copyNames([URL(fileURLWithPath: "/Users/x/Documents/Report.pdf")], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Report.pdf")

        let several = ["/a/Zebra.txt", "/b/apple.tar.gz", "/c/Folder"].map { URL(fileURLWithPath: $0) }
        FileActions.copyNames(several, to: pasteboard)
        let names = pasteboard.string(forType: .string)
        #expect(names == "Zebra.txt\napple.tar.gz\nFolder")
        FileActions.copyPaths(several, to: pasteboard)
        let paths = pasteboard.string(forType: .string)?.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
        #expect(paths?.joined(separator: "\n") == names)
    }

    @Test func copyNameSitsNextToCopyPath() throws {
        let actions = FileAction.allCases
        let path = try #require(actions.firstIndex(of: .copyPath))
        #expect(actions[path + 1] == .copyName)
        #expect(NSImage(systemSymbolName: FileAction.copyName.systemImage, accessibilityDescription: nil) != nil)
    }

    // MARK: Copy to a folder

    @MainActor
    @Test func copiesIntoAFolderKeepingTheOriginals() throws {
        let folder = try workspace()
        let source = folder.appendingPathComponent("Source", isDirectory: true)
        let target = folder.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let report = source.appendingPathComponent("Report.pdf")
        try "pdf".write(to: report, atomically: true, encoding: .utf8)
        // A folder with something inside, an extended attribute and an old date.
        let album = source.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        try "x".write(to: album.appendingPathComponent("Inner/photo.jpg"), atomically: true, encoding: .utf8)
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: report.path)
        #expect(setxattr(report.path, "com.example.tag", "kept", 4, 0, 0) == 0)

        let clipboard = NSPasteboard.general.changeCount
        let first = FileActions.copy([report, album], into: target)
        #expect(first.failures.isEmpty)
        #expect(first.copied.map(\.lastPathComponent) == ["Report.pdf", "Album"])
        // The originals stay, and the clipboard is left alone.
        #expect(FileManager.default.fileExists(atPath: report.path) && FileManager.default.fileExists(atPath: album.path))
        #expect(NSPasteboard.general.changeCount == clipboard)
        // Everything inside, the attribute and the date come along.
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Album/Inner/photo.jpg").path))
        var value = [CChar](repeating: 0, count: 8)
        #expect(getxattr(target.appendingPathComponent("Report.pdf").path, "com.example.tag", &value, 8, 0, 0) == 4)
        let copiedDate = try FileManager.default.attributesOfItem(atPath: target.appendingPathComponent("Report.pdf").path)[.modificationDate] as? Date
        #expect(copiedDate == old)

        // Again: the names are taken, so the copies are numbered, never overwritten.
        let second = FileActions.copy([report, album], into: target)
        #expect(second.copied.map(\.lastPathComponent) == ["Report 2.pdf", "Album 2"])
        // Into the file's own folder: a duplicate beside it.
        #expect(FileActions.copy([report], into: source).copied.map(\.lastPathComponent) == ["Report 2.pdf"])
        #expect(try String(contentsOf: target.appendingPathComponent("Report.pdf"), encoding: .utf8) == "pdf")
    }
}
