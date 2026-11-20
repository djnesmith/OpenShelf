import AppKit
import Testing
@testable import OpenShelf

/// `jk` leaves insert mode (ROADMAP C12 item 2).
@MainActor
struct InsertEscapeTests {
    static func fresh(_ sequence: String? = nil) -> InsertEscape {
        let defaults = UserDefaults(suiteName: "OpenShelfTests.escape.\(UUID())")!
        if let sequence { defaults.set(sequence, forKey: InsertEscape.sequenceKey) }
        return InsertEscape(defaults: defaults)
    }

    @Test func jThenKQuicklyEscapes() {
        var escape = Self.fresh()
        do { let r = escape.typed("j", at: 1.0); #expect(!r) }
        do { let r = escape.typed("k", at: 1.1); #expect(r) }
        // Slower than the delay, or with a key between: plain text.
        do { let r = escape.typed("j", at: 2.0); #expect(!r) }
        do { let r = escape.typed("k", at: 2.3); #expect(!r) }
        do { let r = escape.typed("j", at: 3.0); #expect(!r) }
        do { let r = escape.typed("x", at: 3.05); #expect(!r) }
        do { let r = escape.typed("k", at: 3.1); #expect(!r) }
        // k alone, or k then j, never escapes.
        do { let r = escape.typed("k", at: 4.0); #expect(!r) }
        do { let r = escape.typed("j", at: 4.05); #expect(!r) }
        #expect(escape.delay == 0.15)
    }

    @Test func theSequenceCanBeChangedOrTurnedOff() {
        var jj = Self.fresh("jj")
        do { let r = jj.typed("j", at: 0); #expect(!r) }
        do { let r = jj.typed("j", at: 0.05); #expect(r) }
        var off = Self.fresh("")
        do { let r = off.typed("j", at: 0); #expect(!r) }
        do { let r = off.typed("k", at: 0.05); #expect(!r) }
    }

    /// In the window: the j that went in as text is taken back, and the mode is normal.
    @Test func theWindowLeavesInsertMode() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("ab")
        view.keyDown(with: VimEditorWindowTests.key("A"))
        view.insertText("j", replacementRange: view.selectedRange())
        _ = view.insertEscape.typed("j", at: 0)
        view.keyDown(with: VimEditorWindowTests.key("k"))
        #expect(view.engine.mode == .normal)
        #expect(view.string == "ab")
    }
}
