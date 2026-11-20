import AppKit
import Testing
@testable import OpenShelf

/// ⌥J / ⌥K move lines, as David's Doom config does (~/.doom.d/config.el my/move-line-*).
/// The text matches vim's :m (`2m3`, `2m0`, `2,3m4`, `3,4m1`, `2m5`); the cursor keeps its column.
struct VimMoveLinesTests {
    static let cases: [(String, String, String)] = [
        ("a\nb|cd\nc\nd\ne", "<A-j>", "a\nc\nb|cd\nd\ne"),
        ("a\nb|cd\nc\nd\ne", "<A-k>", "b|cd\na\nc\nd\ne"),
        ("a\nb|cd\nc\nd\ne", "3<A-j>", "a\nc\nd\ne\nb|cd"),
        ("a\nb|cd\nc\nd\ne", "<A-j>u", "a\nb|cd\nc\nd\ne"),
        ("a\nb|cd\nc\nd\ne", "qa<A-j>q@a", "a\nc\nd\nb|cd\ne"),
    ]

    @Test(arguments: cases)
    func movesTheLine(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    /// The selected lines move and stay selected in visual line mode, ready to move again.
    @Test func movesSelectedLinesAndKeepsThemSelected() {
        var engine = VimEngineTests.engine("a\n|bcd\nc\nd\ne")
        _ = engine.handle(VimEngineTests.keys("Vj<A-j>"))
        #expect(engine.string == "a\nd\nbcd\nc\ne")
        #expect(engine.mode == .visualLine)
        #expect(engine.selection.map { String(engine.string.dropFirst($0.lowerBound).prefix($0.count)) } == "bcd\nc\n")
        _ = engine.handle(VimEngineTests.keys("<A-j>"))
        #expect(engine.string == "a\nd\ne\nbcd\nc")
        var up = VimEngineTests.engine("a\nb\n|c\nd\ne")
        _ = up.handle(VimEngineTests.keys("vj<A-k>"))
        #expect(up.string == "a\nc\nd\nb\ne")
        #expect(up.mode == .visualLine)
    }

    /// At the first or last line nothing moves, silently, with the gray note.
    @Test func atTheEdgeNothingMoves() {
        var last = VimEngineTests.engine("a\n|b")
        _ = last.handle(VimEngineTests.keys("<A-j>"))
        #expect(last.string == "a\nb")
        #expect(last.failureHint == "⌥J: no line below")
        // A count past the end moves nothing, as vim's :m refuses a line that isn't there.
        var far = VimEngineTests.engine("a\n|b\nc\nd")
        _ = far.handle(VimEngineTests.keys("5<A-j>"))
        #expect(far.string == "a\nb\nc\nd")
        #expect(far.failureHint == "5⌥J: no line below")
        var first = VimEngineTests.engine("|a\nb")
        _ = first.handle(VimEngineTests.keys("<A-k>"))
        #expect(first.failureHint == "⌥K: no line above")
        var selected = VimEngineTests.engine("|a\nb\nc")
        _ = selected.handle(VimEngineTests.keys("Vj<A-k>"))
        #expect(selected.string == "a\nb\nc")
        #expect(selected.mode == .visualLine)
    }

    /// ⌥J ⌥K ⌥↓ ⌥↑ are caught by key code, so "∆" and "˚" are never typed outside insert mode.
    @MainActor
    @Test func theWindowCatchesOptionJAndK() {
        func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        #expect(VimTextView.vimKey(for: key("∆", 38, .option)) == .alt("j"))
        #expect(VimTextView.vimKey(for: key("˚", 40, .option)) == .alt("k"))
        #expect(VimTextView.vimKey(for: key("", 125, [.option, .numericPad, .function])) == .alt("j"))
        #expect(VimTextView.vimKey(for: key("", 126, [.option, .numericPad, .function])) == .alt("k"))
        // ⌥⌘ keys (⌥⌘L, ⌥⌘Z) and plain J are not moves.
        #expect(VimTextView.vimKey(for: key("j", 38, [.option, .command])) != .alt("j"))
        #expect(VimTextView.vimKey(for: key("j", 38, [])) == .char("j"))
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("one\ntwo")
        view.keyDown(with: key("∆", 38, .option))
        #expect(view.string == "two\none")
    }
}
