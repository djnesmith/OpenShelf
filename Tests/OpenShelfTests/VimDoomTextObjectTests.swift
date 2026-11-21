import Testing
@testable import OpenShelf

/// Text objects David's Doom Emacs has and vim doesn't (ROADMAP C17-C24). Same notation as
/// VimEngineTests; every expected result is what evil and Doom's packages do, run in
/// `emacs --batch` with his installed packages (~/.config/emacs/.local/straight/build-31.1)
/// in a plain buffer.
struct VimDoomTextObjectTests {
    static func run(_ start: String, _ keys: String) -> String {
        VimEngineTests.marked(VimEngineTests.run(start, keys))
    }
    /// iq / aq, Doom's any quote (C17): the smallest quoted text of any kind wins.
    @Test(arguments: [
        ("say \"he|llo\" now", "diq", "say \"|\" now"),
        ("say \"he|llo\" now", "daq", "say | now"),
        ("say \"hello|\"", "daq", "say| "),
        ("x  \"a|b\"  y", "daq", "x  |  y"),
        ("|say \"hello\" now", "diq", "say \"|\" now"),
        ("say \"a 'b|' c\" d", "diq", "say \"a '|' c\" d"),
        ("say \"a 'b' |c\" d", "diq", "say \"|\" d"),
        ("say 'a \"b\" |c' d", "daq", "say |d"),
        ("x `co|de` y", "ciqZ<Esc>", "x `|Z` y"),
        ("a \"b\" |c \"d\"", "diq", "a \"b\" c \"|\""),
        ("a \"b\nc|d\" e", "diq", "a \"|\" e"),
        ("no quotes| here", "diq", "no quotes| here"),
        ("(str \"a \\\"b|\\\" c\")", "diq", "(str \"|\")"),
        ("say “cur|ly” x", "diq", "say “|” x"),
        ("say \"he|llo\" now", "2diq", "say | now"),
        ("say \"he|llo\" now", "viqd", "say \"|\" now"),
        ("say |\"hello\" now", "diq", "say \"|\" now"),
        ("say \"hello|\" now", "diq", "say \"|\" now"),
        ("it's \"a|b\"", "diq", "it's \"|\""),
        ("a |\"b\" 'c'", "daq", "a |'c'"),
        ("a 'b' |\"c\"", "diq", "a 'b' \"|\""),
        ("\"a\" b| \"c\"", "ciqX<Esc>", "\"a\" b \"|X\""),
        ("say \"\" |x", "diq", "say \"|\" x"),
        ("say |\"hello\" now", "daq", "say |now"),
        ("say \"h|\" now", "daq", "say | now"),
        ("say 'he|llo' now", "daq", "say |now"),
        ("say `he|llo` now", "daq", "say |now"),
        ("say “he|llo” now", "daq", "say | now"),
        ("say 'a|bcdef' x \"d\"", "diq", "say 'abcdef' x \"|\""),
        ("say \"a|bcdef\" x 'd'", "diq", "say \"|\" x 'd'"),
        ("q |x 'abcdef' \"d\"", "diq", "q x 'abcdef' \"|\""),
        ("(a\n  \"b|c\")", "diq", "(a\n  \"|\")"),
        ("(a \"x\")\n(b \"y|z\")", "diq", "(a \"x\")\n(b \"|\")"),
        ("a \"b c\" d \"e| f\"", "vaqd", "a \"b c\" d| "),
        ("say \"he|llo\" now", "caqX<Esc>", "say |X now"),
        ("x 'it\\'s|' y", "diq", "x '|' y"),
        ("(foo \"b|ar\" :k \"v\")", "ciqX<Esc>", "(foo \"|X\" :k \"v\")"),
        ("(fo|o \"bar\" :k \"v\")", "ciqX<Esc>", "(foo \"|X\" :k \"v\")"),
        ("say \"ab\" |x", "diq", "say \"|\" x"),
        ("say \"ab\" |x y", "diq", "say \"|\" x y"),
        ("say 'ab' |x", "diq", "say '|' x"),
        ("say \"ab\" |x\nmore", "diq", "say \"|\" x\nmore"),
        ("say \"ab\"| x", "diq", "say \"|\" x"),
        ("\"a\" \"bcd\" |x", "diq", "\"a\" \"|\" x"),
        ("\"abc\" \"d\" |x", "diq", "\"abc\" \"|\" x"),
        ("'abc' \"d\" |x", "diq", "'abc' \"|\" x"),
        ("\"ab\" x|\n\"cd\"", "diq", "\"ab\" x\n\"|\""),
        ("(a \"b\")\n(c |d)", "diq", "(a \"|\")\n(c d)"),
    ])
    func anyQuote(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// ig / ag, Doom's whole buffer (C20).
    @Test(arguments: [
        ("one\n|two\nthree", "dig", "|"),
        ("one\n|two\nthree\n", "dag", "|"),
        ("one\n|two\nthree", "cigZ<Esc>", "|Z"),
        ("one\n|two\nthree", "yig", "|one\ntwo\nthree"),
        ("one\n|two\nthree", "gUig", "|ONE\nTWO\nTHREE"),
        ("one\n|two\nthree", "vigd", "|"),
        ("one\n|two\nthree", "Vigd", "|"),
        ("|", "dig", "|"),
        ("a\n\n|b\n", "g~ag", "|A\n\nB\n"),
        ("one t|wo", "ysigb", "|(one two)"),
        ("x |y", "2dig", "|"),
    ])
    func wholeText(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }
}
