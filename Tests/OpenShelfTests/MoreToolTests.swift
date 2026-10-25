import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import OpenShelf

/// Transcription helpers and the other non-media tools.
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

    // MARK: Copy and Move to a folder

    /// A source folder holding Report.pdf (with an extended attribute and an old
    /// date) and Album/Inner/photo.jpg, a target folder, and a test trash.
    func transferWorkspace() throws -> (source: URL, target: URL, trash: URL, report: URL, album: URL) {
        let folder = try workspace()
        let source = folder.appendingPathComponent("Source", isDirectory: true)
        let target = folder.appendingPathComponent("Target", isDirectory: true)
        let trash = folder.appendingPathComponent("Trash", isDirectory: true)
        for url in [source, target, trash] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let report = source.appendingPathComponent("Report.pdf")
        try "new".write(to: report, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: report.path)
        #expect(setxattr(report.path, "com.example.tag", "kept", 4, 0, 0) == 0)
        let album = source.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        try "x".write(to: album.appendingPathComponent("Inner/photo.jpg"), atomically: true, encoding: .utf8)
        return (source, target, trash, report, album)
    }

    /// Stubs: a fixed answer, as a pure function of the clash.
    static func always(_ choice: FileActions.ConflictChoice, applyToAll: Bool = false) -> FileActions.ConflictPrompt {
        { _, _, _ in FileActions.ConflictDecision(choice: choice, applyToAll: applyToAll) }
    }

    static func never(_ name: String, _ destination: URL, _ offersApplyToAll: Bool) -> FileActions.ConflictDecision {
        Issue.record("Asked about \(name) without a clash")
        return FileActions.ConflictDecision(choice: .skip)
    }

    func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @MainActor
    @Test func copiesIntoAFolderKeepingTheOriginals() throws {
        let (_, target, _, report, album) = try transferWorkspace()
        let clipboard = NSPasteboard.general.changeCount
        let result = FileActions.transfer([report, album], into: target, operation: .copy, prompt: Self.never)
        #expect(result.done.map(\.lastPathComponent) == ["Report.pdf", "Album"] && result.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: report.path) && FileManager.default.fileExists(atPath: album.path))
        #expect(NSPasteboard.general.changeCount == clipboard)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Album/Inner/photo.jpg").path))
        var value = [CChar](repeating: 0, count: 8)
        #expect(getxattr(target.appendingPathComponent("Report.pdf").path, "com.example.tag", &value, 8, 0, 0) == 4)
        let date = try FileManager.default.attributesOfItem(atPath: target.appendingPathComponent("Report.pdf").path)[.modificationDate] as? Date
        #expect(date == Date(timeIntervalSince1970: 1_000_000_000))
    }

    @MainActor
    @Test func keepBothNumbersTheNewOne() throws {
        let (_, target, _, report, album) = try transferWorkspace()
        try "old".write(to: target.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Album"), withIntermediateDirectories: true)
        let result = FileActions.transfer([report, album], into: target, operation: .copy, prompt: Self.always(.keepBoth))
        #expect(result.done.map(\.lastPathComponent) == ["Report 2.pdf", "Album 2"])
        #expect(try text(target.appendingPathComponent("Report.pdf")) == "old")
    }

    @MainActor
    @Test func overwriteSendsTheOldOneToTheTrash() throws {
        let (_, target, trash, report, album) = try transferWorkspace()
        try "old".write(to: target.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        // An existing folder is replaced whole, not merged.
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Album/OnlyInOld"), withIntermediateDirectories: true)
        let toTestTrash: (URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) }
        let result = FileActions.transfer([report, album], into: target, operation: .move, prompt: Self.always(.overwrite), trash: toTestTrash)
        #expect(result.done.count == 2 && result.failures.isEmpty)
        #expect(try text(target.appendingPathComponent("Report.pdf")) == "new")
        #expect(try text(trash.appendingPathComponent("Report.pdf")) == "old")
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Album/OnlyInOld").path))
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("Album/OnlyInOld").path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Album/Inner/photo.jpg").path))
        // Moved, so gone from the source.
        #expect(!FileManager.default.fileExists(atPath: report.path))
    }

    @MainActor
    @Test func cancelLeavesEverythingAsItWas() throws {
        let (_, target, trash, report, _) = try transferWorkspace()
        try "old".write(to: target.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        let result = FileActions.transfer([report], into: target, operation: .move, prompt: Self.always(.skip)) { _ in Issue.record("Trashed on Cancel") }
        #expect(result.done.isEmpty && result.skipped == 1)
        #expect(try text(report) == "new" && (try text(target.appendingPathComponent("Report.pdf"))) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    @MainActor
    @Test func applyToAllAsksOnce() throws {
        let (source, target, _, _, _) = try transferWorkspace()
        let names = ["a.txt", "b.txt", "c.txt"]
        for name in names {
            try "new".write(to: source.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try "old".write(to: target.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let files = names.map { source.appendingPathComponent($0) }
        // Without Apply to all, each file is asked about; the answer depends only on its name.
        let perFile: FileActions.ConflictPrompt = { name, _, offersApplyToAll in
            #expect(offersApplyToAll == (name != "c.txt"), "\(name)")
            return FileActions.ConflictDecision(choice: name == "b.txt" ? .skip : .keepBoth)
        }
        let each = FileActions.transfer(files, into: target, operation: .copy, prompt: perFile)
        #expect(each.done.map(\.lastPathComponent) == ["a 2.txt", "c 2.txt"] && each.skipped == 1)

        // With it, the first answer is used for the rest: only a.txt is asked about.
        let once: FileActions.ConflictPrompt = { name, _, _ in
            #expect(name == "a.txt", "asked about \(name) after Apply to all")
            return FileActions.ConflictDecision(choice: .skip, applyToAll: true)
        }
        let all = FileActions.transfer(files, into: target, operation: .copy, prompt: once)
        #expect(all.done.isEmpty && all.skipped == 3)
    }

    @MainActor
    @Test func ontoItselfNeedsNoQuestion() throws {
        let (source, _, _, report, _) = try transferWorkspace()
        let copy = FileActions.transfer([report], into: source, operation: .copy, prompt: Self.never)
        #expect(copy.done.map(\.lastPathComponent) == ["Report 2.pdf"])
        let move = FileActions.transfer([report], into: source, operation: .move, prompt: Self.never)
        #expect(move.done.isEmpty && move.failures.isEmpty && FileManager.default.fileExists(atPath: report.path))
    }
}
