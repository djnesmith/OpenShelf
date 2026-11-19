import Testing
@testable import OpenShelf

/// The Edit window's clipboard rule (David, 2026-11-19): yanks go on the Mac
/// clipboard, deletes and changes never do, and p and P with no register
/// always paste the Mac clipboard. A deliberate difference from vim.
struct VimClipboardTests {
    /// A stand-in for NSPasteboard: its text and a change count.
    final class Board: @unchecked Sendable {
        var text: String?
        var changeCount = 0
        init(_ text: String? = nil) { self.text = text }
        func copy(_ text: String) {
            self.text = text
            changeCount += 1
        }
    }

    static func engine(_ marked: String, board: Board) -> VimEngine {
        var engine = VimEngineTests.engine(marked)
        engine.usesSystemClipboard = true
        engine.clipboard = VimClipboard(read: { board.text }, write: { board.copy($0) })
        return engine
    }

    @Test func yanksGoOnTheClipboard() {
        let board = Board()
        var engine = Self.engine("|one two", board: board)
        _ = engine.handle(VimEngineTests.keys("yw"))
        #expect(board.text == "one ")
        #expect(board.changeCount == 1)
        _ = engine.handle(VimEngineTests.keys("yy"))
        #expect(board.text == "one two\n")
        _ = engine.handle(VimEngineTests.keys("Y"))
        #expect(board.text == "one two")
        _ = engine.handle(VimEngineTests.keys("wviwy"))
        #expect(board.text == "two")
        #expect(board.changeCount == 4)
    }

    @Test func namedAndBlackHoleYanksLeaveTheClipboard() {
        let board = Board("outside")
        var engine = Self.engine("|one two", board: board)
        _ = engine.handle(VimEngineTests.keys("\"ayw\"_yw"))
        #expect(board.changeCount == 0)
        #expect(engine.registers["a"]?.text == "one ")
    }

    @Test(arguments: ["x", "X", "dw", "dd", "D", "cwZ<Esc>", "ccZ<Esc>", "CZ<Esc>", "sZ<Esc>", "SZ<Esc>", "vld", "vlcZ<Esc>", "vlx"])
    func deletesAndChangesNeverTouchTheClipboard(keys: String) {
        let board = Board("outside")
        var engine = Self.engine("o|ne two", board: board)
        _ = engine.handle(VimEngineTests.keys(keys))
        #expect(board.changeCount == 0, "\(keys)")
        #expect(board.text == "outside")
    }

    @Test func pAlwaysPastesTheClipboard() {
        let board = Board("CLIP")
        // dd then p pastes the clipboard, not the deleted line.
        var engine = Self.engine("|one\ntwo", board: board)
        _ = engine.handle(VimEngineTests.keys("ddp"))
        #expect(engine.string == "tCLIPwo")
        // xp no longer swaps: it pastes the clipboard.
        var swap = Self.engine("|ab", board: board)
        _ = swap.handle(VimEngineTests.keys("xp"))
        #expect(swap.string == "bCLIP")
        // A copy made outside, then p.
        var outside = Self.engine("|ab", board: board)
        board.copy("new")
        _ = outside.handle(VimEngineTests.keys("P"))
        #expect(outside.string == "newab")
        // The deleted text is still there in the unnamed register, by name.
        var named = Self.engine("|one two", board: board)
        _ = named.handle(VimEngineTests.keys("dw\"\"P"))
        #expect(named.string == "one two")
    }

    @Test func linesPasteAsLines() {
        let board = Board()
        var engine = Self.engine("|one\ntwo", board: board)
        _ = engine.handle(VimEngineTests.keys("yyjp"))
        #expect(engine.string == "one\ntwo\none")
        board.copy("outside\n")
        _ = engine.handle(VimEngineTests.keys("ggP"))
        #expect(engine.string == "outside\none\ntwo\none")
    }

    /// Visual p pastes the clipboard and leaves it as it was.
    @Test func visualPutReplacesWithTheClipboard() {
        let board = Board("CLIP")
        var engine = Self.engine("|one two", board: board)
        _ = engine.handle(VimEngineTests.keys("viwp"))
        #expect(engine.string == "CLIP two")
        #expect(board.text == "CLIP")
        #expect(board.changeCount == 0)
    }

    /// A macro reads the clipboard when it plays, not when it was recorded.
    @Test func macrosReadTheClipboardWhenTheyPlay() {
        let board = Board("first")
        var engine = Self.engine("|a\nb", board: board)
        _ = engine.handle(VimEngineTests.keys("qaPjq"))
        board.copy("second")
        _ = engine.handle(VimEngineTests.keys("@a"))
        #expect(engine.string == "firsta\nsecondb")
    }

    /// Nothing on the clipboard (or only a picture): p says so, and visual p
    /// leaves the selection, as vim does with an empty register.
    @Test func anEmptyClipboardPutsNothing() {
        let board = Board()
        var plain = Self.engine("|ab", board: board)
        _ = plain.handle(VimEngineTests.keys("p"))
        #expect(plain.string == "ab")
        #expect(plain.message == "E353: Nothing in register")
        var visual = Self.engine("|ab cd", board: board)
        _ = visual.handle(VimEngineTests.keys("viwp"))
        #expect(visual.string == "ab cd")
        #expect(visual.message == "E353: Nothing in register")
    }
}
