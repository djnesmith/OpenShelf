import Foundation
import Testing
@testable import OpenShelf

/// `R`, `gv` and `o` in visual line mode (ROADMAP C12 item 6). Expected results are vim 9.2's.
struct VimReplaceModeTests {
    @Test(arguments: [
        ("|abcdef", "RXY<Esc>", "X|Ycdef"),
        ("|abcdef", "3RX<Esc>", "XX|Xdef"),
        ("|abcdef", "2RXY<Esc>", "XYX|Yef"),
        ("|abcdef", "RXY<BS><Esc>", "|Xbcdef"),
        ("|ab", "RWXYZ<Esc>", "WXY|Z"),
        ("ab|c", "RX<BS><BS><Esc>", "|abc"),
        ("|ab", "RXYZ<BS><BS><Esc>", "|Xb"),
        ("|abc\ndef", "RXY<Esc>j.", "XYc\ndX|Y"),
        ("|abc def", "RX<Esc>w.", "Xbc |Xef"),
        ("|abc", "RX<Esc>u", "|abc"),
        ("|abc def", "vlo<Esc>gvd", "|c def"),
        ("a|bcdef", "vll<Esc>0gv<Esc>", "abc|def"),
        ("a\n|b\nc", "Vjokd", "|"),
    ])
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    /// R with nothing typed leaves no undo step: u takes back the change before it.
    @Test func anEmptyReplaceIsNoUndoStep() {
        var engine = VimEngineTests.engine("|abc")
        _ = engine.handle(VimEngineTests.keys("xR<Esc>u"))
        #expect(engine.string == "abc")
    }

    @Test func showsReplaceAndGvNeedsASelection() {
        var engine = VimEngineTests.engine("|abc")
        _ = engine.handle(VimEngineTests.keys("R"))
        #expect(engine.mode == .replace)
        #expect(engine.modeName == "REPLACE")
        var fresh = VimEngineTests.engine("|abc")
        _ = fresh.handle(VimEngineTests.keys("gv"))
        #expect(fresh.mode == .normal)
        #expect(fresh.failureHint != nil)
    }
}
