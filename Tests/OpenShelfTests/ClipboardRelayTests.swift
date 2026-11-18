import AppKit
import Foundation
import Testing
@testable import OpenShelf

/// A clipboard in memory that logs what happens to it, in order.
@MainActor
final class FakeTextPasteboard: TextPasteboard {
    var items: [[NSPasteboard.PasteboardType: Data]]
    private(set) var changeCount = 0
    var log: [String] = []

    init(text: String) {
        items = [[.string: Data(text.utf8)]]
    }

    /// Something else (the app, the user) writes to the clipboard.
    func appWrites(_ text: String, html: String? = nil) {
        var item: [NSPasteboard.PasteboardType: Data] = [.string: Data(text.utf8)]
        if let html { item[.html] = Data(html.utf8) }
        items = [item]
        changeCount += 1
        log.append("app wrote \(text)")
    }

    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }

    func restore(_ snapshot: PasteboardSnapshot) {
        items = snapshot.items
        changeCount += 1
        log.append("restore")
    }

    func writeTransient(_ text: String) {
        items = [[.string: Data(text.utf8), NSPasteboard.PasteboardType("org.nspasteboard.TransientType"): Data()]]
        changeCount += 1
        log.append("transient \(text)")
    }

    func writeText(_ text: String) {
        items = [[.string: Data(text.utf8)]]
        changeCount += 1
        log.append("text \(text)")
    }

    func string() -> String? { items.first?[.string].map { String(decoding: $0, as: UTF8.self) } }

    func richText() -> RichText? { items.first?[.html].map { RichText(kind: .html, data: $0) } }

    var currentText: String? { string() }
}

/// Records each shortcut and lets the "app" answer it, as a pure function of the key.
@MainActor
final class FakeKeys: TextKeySender {
    let pasteboard: FakeTextPasteboard
    let onPress: @MainActor (TextShortcut, FakeTextPasteboard) -> Void

    init(_ pasteboard: FakeTextPasteboard, onPress: @escaping @MainActor (TextShortcut, FakeTextPasteboard) -> Void = { _, _ in }) {
        self.pasteboard = pasteboard
        self.onPress = onPress
    }

    func press(_ shortcut: TextShortcut) {
        pasteboard.log.append(shortcut == .copy ? "⌘C" : "⌘V")
        onPress(shortcut, pasteboard)
    }
}

@MainActor
struct ClipboardRelayTests {
    func relay(_ pasteboard: FakeTextPasteboard, keys: FakeKeys, sleep: @escaping @MainActor (Duration) async -> Void = { _ in }) -> ClipboardRelay {
        ClipboardRelay(pasteboard: pasteboard, keys: keys, sleep: sleep)
    }

    @Test func copyReadsTheSelectionAndPutsTheClipboardBack() async {
        let pasteboard = FakeTextPasteboard(text: "user's clip")
        let keys = FakeKeys(pasteboard) { shortcut, board in
            if shortcut == .copy { board.appWrites("selected", html: "<b>selected</b>") }
        }
        let copied = await relay(pasteboard, keys: keys).copySelection()
        #expect(copied?.text == "selected")
        #expect(copied?.rich == RichText(kind: .html, data: Data("<b>selected</b>".utf8)))
        #expect(pasteboard.currentText == "user's clip")
        #expect(pasteboard.log == ["⌘C", "app wrote selected", "restore"])
    }

    @Test func copyWithNoAnswerLeavesTheClipboardAlone() async {
        let pasteboard = FakeTextPasteboard(text: "user's clip")
        var slept: Duration = .zero
        let copied = await relay(pasteboard, keys: FakeKeys(pasteboard)) { slept += $0 }.copySelection()
        #expect(copied == nil)
        #expect(pasteboard.log == ["⌘C"])
        #expect(pasteboard.currentText == "user's clip")
        #expect(slept >= ClipboardRelay.copyTimeout)
    }

    /// The watcher is told around each borrow, so it can tell our writes from the user's.
    @Test func borrowsAreAnnounced() async {
        let pasteboard = FakeTextPasteboard(text: "clip")
        var events: [String] = []
        var relay = relay(pasteboard, keys: FakeKeys(pasteboard) { shortcut, board in
            if shortcut == .copy { board.appWrites("sel") }
        })
        relay.willBorrow = { events.append("borrow") }
        relay.didRestore = { events.append("restored") }
        _ = await relay.copySelection()
        await relay.paste("result")
        #expect(events == ["borrow", "restored", "borrow", "restored"])
    }

    @Test func copyWaitsForASlowApp() async {
        let pasteboard = FakeTextPasteboard(text: "clip")
        var polls = 0
        let copied = await relay(pasteboard, keys: FakeKeys(pasteboard)) { _ in
            polls += 1
            if polls == 3 { pasteboard.appWrites("late") }
        }.copySelection()
        #expect(copied?.text == "late")
        #expect(pasteboard.currentText == "clip")
    }

    @Test func pasteWritesMarkedTextPressesPasteThenRestores() async {
        let pasteboard = FakeTextPasteboard(text: "user's clip")
        var sleeps: [Duration] = []
        await relay(pasteboard, keys: FakeKeys(pasteboard)) { sleeps.append($0) }.paste("result")
        #expect(pasteboard.log == ["transient result", "⌘V", "restore"])
        #expect(sleeps == [ClipboardRelay.restoreDelay])
        #expect(pasteboard.currentText == "user's clip")
    }

    @Test func pasteDoesNotRestoreOverANewerCopy() async {
        let pasteboard = FakeTextPasteboard(text: "old")
        await relay(pasteboard, keys: FakeKeys(pasteboard)) { _ in pasteboard.appWrites("copied meanwhile") }.paste("result")
        #expect(pasteboard.log == ["transient result", "⌘V", "app wrote copied meanwhile"])
        #expect(pasteboard.currentText == "copied meanwhile")
    }

    @Test func pastedTextIsMarkedForClipboardManagers() async {
        let pasteboard = FakeTextPasteboard(text: "old")
        var seenDuringPaste: [NSPasteboard.PasteboardType] = []
        let keys = FakeKeys(pasteboard) { shortcut, board in
            if shortcut == .paste { seenDuringPaste = Array(board.items.first?.keys ?? [:].keys) }
        }
        await relay(pasteboard, keys: keys).paste("result")
        #expect(seenDuringPaste.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
    }

    @Test func systemPasteboardRoundTripsEveryType() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("openshelf-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let pasteboard = SystemTextPasteboard(board)
        let png = NSPasteboard.PasteboardType.png
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("text", forType: .string)
        item.setData(Data([1, 2, 3]), forType: png)
        board.writeObjects([item])

        let saved = pasteboard.snapshot()
        pasteboard.writeTransient("borrowed")
        #expect(board.string(forType: .string) == "borrowed")
        #expect(board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == true)
        pasteboard.restore(saved)
        #expect(board.string(forType: .string) == "text")
        #expect(board.data(forType: png) == Data([1, 2, 3]))
        #expect(board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == false)
    }
}
