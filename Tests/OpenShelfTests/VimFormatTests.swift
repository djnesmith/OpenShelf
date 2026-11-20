import Foundation
import Testing
@testable import OpenShelf

/// gq (ROADMAP C12 item 4). Expected results are vim 9.2's (vim --clean, textwidth 0, so 79).
struct VimFormatTests {
    static let long = (0..<30).map { "word\($0)" }.joined(separator: " ")
    static let line79 = "w0 w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14 w15 w16 w17 w18 w19 w20 w21 w"
    static let wrapped = "word0 word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11\nword12 word13 word14 word15 word16 word17 word18 word19 word20 word21 word22\n|word23 word24 word25 word26 word27 word28 word29"

    static let cases: [(String, String, String)] = [
        ("|aa\nbb\ncc\n\ndd", "gqip", "|aa bb cc\n\ndd"),
        ("|" + long, "gqq", wrapped),
        ("  |" + long, "gqq", "  word0 word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11\n  word12 word13 word14 word15 word16 word17 word18 word19 word20 word21 word22\n  |word23 word24 word25 word26 word27 word28 word29"),
        ("x\n|aa\nbb\n\ncc\ndd", "gqG", "x\naa bb\n\n|cc dd"),
        ("|aa  bb\n   cc", "gqip", "|aa  bb cc"),
        ("|aa\nbb\ncc\ndd", "gq2j", "|aa bb cc\ndd"),
        ("|" + long + "\nnext", "gqq", wrapped + "\nnext"),
        // A line of only spaces separates paragraphs too.
        ("|aa\n  \nbb", "gqG", "aa\n  \n|bb"),
        // Exactly 79 characters fit; the word after them goes down.
        ("|" + line79 + " yy", "gqq", line79 + "\n|yy"),
        ("|" + line79, "gqq", "|" + line79),
    ]

    @Test(arguments: cases)
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    /// gq that changes nothing leaves no undo step: u takes back the change before it.
    @Test func anUnchangedFormatIsNoUndoStep() {
        var engine = VimEngineTests.engine("|abc")
        _ = engine.handle(VimEngineTests.keys("xgqqu"))
        #expect(engine.string == "abc")
    }

    @Test func aLongWordStaysWholeAndUndoIsOneStep() {
        let word = String(repeating: "x", count: 100)
        #expect(VimFormat.breakLine("a \(word) b", indent: "", width: 79) == ["a", word, "b"])
        var engine = VimEngineTests.engine("|aa\nbb")
        _ = engine.handle(VimEngineTests.keys("gqipu"))
        #expect(engine.string == "aa\nbb")
    }
}
