import Foundation
import Testing
@testable import OpenShelf

/// ⌃A and ⌃X (ROADMAP C12 item 5). Expected results are vim 9.2's (vim --clean).
struct VimNumberTests {
    @Test(arguments: [
        ("|x 41 y", "<C-a>", "x 4|2 y"),
        ("x 4|1 y", "5<C-a>", "x 4|6 y"),
        ("|x 10 y", "<C-x>", "x |9 y"),
        ("|-3", "5<C-a>", "|2"),
        ("|a-3", "<C-a>", "a-|2"),
        ("|007", "<C-a>", "00|8"),
        ("|0x0f", "<C-a>", "0x1|0"),
        ("|0xFF", "<C-a>", "0x10|0"),
        ("|0b101", "<C-a>", "0b11|0"),
        ("|no digits", "<C-a>", "|no digits"),
        ("|x 9", "<C-a>", "x 1|0"),
        ("|1", "<C-x><C-x>", "-|1"),
        ("a1b2|", "<C-a>", "a1b|3"),
        ("|9 9", "<C-a>w.", "10 1|0"),
        ("|word5", "<C-a>", "word|6"),
        ("|-0", "<C-x>", "-|1"),
        ("|x 0x", "<C-a>", "x |1x"),
        ("|0xAE", "<C-a>", "0xA|F"),
        ("|0x00ff", "<C-a>", "0x010|0"),
        ("|0b0011", "<C-a>", "0b010|0"),
    ])
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    @Test func noNumberFailsAndUndoIsOneStep() {
        var engine = VimEngineTests.engine("|none")
        _ = engine.handle(VimEngineTests.keys("<C-a>"))
        #expect(engine.failureHint != nil)
        var other = VimEngineTests.engine("|5")
        _ = other.handle(VimEngineTests.keys("3<C-a>u"))
        #expect(other.string == "5")
    }
}
