import AppKit
import Testing
@testable import OpenShelf

/// Visual block, ⌃V (ROADMAP C12 item 3). Expected results are vim 9.2's (vim --clean).
struct VimBlockTests {
    static let cases: [(String, String, String)] = [
        ("|abcd\nefgh\nijkl", "<C-v>jld", "|cd\ngh\nijkl"),
        ("a|bcd\nefgh\nijkl", "<C-v>jjIXY<Esc>", "a|XYbcd\neXYfgh\niXYjkl"),
        ("a|bcd\nefgh\nijkl", "<C-v>jjlAXY<Esc>", "a|bcXYd\nefgXYh\nijkXYl"),
        ("|ab\nabcd\na", "<C-v>jj$AX<Esc>", "|abX\nabcdX\naX"),
        ("|abcd\nab\nabcd", "<C-v>jjllAX<Esc>", "|abcXd\nab X\nabcXd"),
        ("a|bcd\nefgh", "<C-v>jlcZ<Esc>", "a|Zd\neZh"),
        ("|abcd\nefgh", "<C-v>jlrX", "|XXcd\nXXgh"),
        ("|abcd\nefgh", "<C-v>jlyP", "|ababcd\nefefgh"),
        ("a|bcd\nefgh\nijkl", "<C-v>jjlx", "a|d\neh\nil"),
        ("|abcd\nefgh", "<C-v>jlU", "|ABcd\nEFgh"),
        ("|abcd\nefgh\nijkl", "<C-v>jlo<Esc>", "|abcd\nefgh\nijkl"),
        ("|abcd\nefgh\nijkl", "<C-v>jlO<Esc>", "abcd\n|efgh\nijkl"),
        ("|abc\n\nabc", "<C-v>jjIX<Esc>", "|Xabc\nX\nXabc"),
        ("|abcd\nefgh", "<C-v>j$d", "|\n"),
        ("|abcd\nefgh\nij", "<C-v>jjlld", "|d\nh\n"),
        // $ reaches every line's end, even when the cursor is on a short line.
        ("|abcd\nab", "<C-v>j$d", "|\n"),
        // I leaves a line too short to reach the block alone.
        ("a|bcd\n\nabcd", "<C-v>jjIX<Esc>", "a|Xbcd\n\naXbcd"),
        // A pads a short first line too, and only the typed text goes to the others.
        ("|ab\nabcd\nabcd", "<C-v>jjllAX<Esc>", "|ab X\nabcXd\nabcXd"),
        // A block pasted past a short line's end pads it.
        ("|ab\nefgh\nxyzw\nq", "<C-v>jly jj$p", "ab\nefgh\nxyzw|ab\nq   ef"),
    ]

    @Test(arguments: cases)
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    /// In the window, yank puts the block on the Mac clipboard; p still pastes it as a block.
    @Test func aBlockFromTheClipboardPastesAsABlock() {
        final class Board: @unchecked Sendable { var text: String? }
        let board = Board()
        var engine = VimEngineTests.engine("|abcd\nefgh")
        engine.usesSystemClipboard = true
        engine.clipboard = VimClipboard(read: { board.text }, write: { board.text = $0 })
        _ = engine.handle(VimEngineTests.keys("<C-v>jly"))
        #expect(board.text == "ab\nef")
        _ = engine.handle(VimEngineTests.keys("P"))
        #expect(engine.string == "ababcd\nefefgh")
    }

    @Test func selectsARectangleAndSaysSo() {
        var engine = VimEngineTests.engine("|abcd\nef\nijkl")
        _ = engine.handle(VimEngineTests.keys("<C-v>jjl"))
        #expect(engine.mode == .visualBlock)
        #expect(engine.modeName == "VISUAL BLOCK")
        #expect(engine.blockSelection == [0..<2, 5..<7, 8..<10])
        _ = engine.handle(VimEngineTests.keys("<C-v>"))
        #expect(engine.mode == .normal)
    }

    /// The window shows a block as one selection per line.
    @MainActor
    @Test func theWindowShowsOneRangePerLine() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("abcd\nefgh")
        view.keyDown(with: VimEditorWindowTests.key("v", keyCode: 9, modifiers: .control))
        for c in "jl" { view.keyDown(with: VimEditorWindowTests.key(String(c))) }
        #expect(view.selectedRanges.map(\.rangeValue) == [NSRange(location: 0, length: 2), NSRange(location: 5, length: 2)])
    }
}
