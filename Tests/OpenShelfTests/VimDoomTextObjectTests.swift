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

    /// ii ai ik ak ij aj, evil-indent-plus (C19).
    @Test(arguments: [
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUii", "def f():\n    a = 1\n    if a:\n|        B\n    c\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUai", "def f():\n    a = 1\n    if a:\n|        B\n    c\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUik", "def f():\n    a = 1\n|    IF A:\n        B\n    c\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUak", "def f():\n    a = 1\n|    IF A:\n        B\n    c\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUij", "def f():\n    a = 1\n|    IF A:\n        B\n    C\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "gUaj", "def f():\n    a = 1\n|    IF A:\n        B\n    C\n\nd"),
        ("def f():\n    a = 1\n    if a:\n        b|\n    c\n\nd", "dii", "def f():\n    a = 1\n    if a:\n|\n    c\n\nd"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUii", "def f():\n|    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\ne = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUai", "def f():\n|    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\ne = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUik", "|DEF F():\n    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\ne = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUak", "|DEF F():\n    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\ne = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUij", "|DEF F():\n    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\nE = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "gUaj", "|DEF F():\n    A = 1\n\n    B = 2\n    IF B:\n        C\n\n\nE = 3\n"),
        ("def f():\n    a| = 1\n\n    b = 2\n    if b:\n        c\n\n\ne = 3\n", "dii", "def f():\n|\n\n\ne = 3\n"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUii", "(defn f [x]\n  (let [a 1]\n|    (+ A X))\n  (g x))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUai", "(defn f [x]\n  (let [a 1]\n|    (+ A X))\n  (g x))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUik", "(defn f [x]\n|  (LET [A 1]\n    (+ A X))\n  (g x))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUak", "(defn f [x]\n|  (LET [A 1]\n    (+ A X))\n  (g x))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUij", "(defn f [x]\n|  (LET [A 1]\n    (+ A X))\n  (G X))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "gUaj", "(defn f [x]\n|  (LET [A 1]\n    (+ A X))\n  (G X))\n\n(h)"),
        ("(defn f [x]\n  (let [a 1]\n    (+ a| x))\n  (g x))\n\n(h)", "dii", "(defn f [x]\n  (let [a 1]\n|\n  (g x))\n\n(h)"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUii", "top\n\n|  ONE\n  TWO\n\n\n  THREE\nback"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUai", "top\n|\n  ONE\n  TWO\n\n\n  THREE\nback"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUik", "|TOP\n\n  ONE\n  TWO\n\n\n  THREE\nback"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUak", "|TOP\n\n  ONE\n  TWO\n\n\n  THREE\nback"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUij", "|TOP\n\n  ONE\n  TWO\n\n\n  THREE\nBACK"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "gUaj", "|TOP\n\n  ONE\n  TWO\n\n\n  THREE\nBACK"),
        ("top\n\n  one\n  t|wo\n\n\n  three\nback", "dii", "top\n\n|\nback"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUii", "a\n|\tB\n\t\tC\n        D\ne"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUai", "a\n|\tB\n\t\tC\n        D\ne"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUik", "|A\n\tB\n\t\tC\n        D\ne"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUak", "|A\n\tB\n\t\tC\n        D\ne"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUij", "|A\n\tB\n\t\tC\n        D\nE"),
        ("a\n\tb|\n\t\tc\n        d\ne", "gUaj", "|A\n\tB\n\t\tC\n        D\nE"),
        ("a\n\tb|\n\t\tc\n        d\ne", "dii", "a\n|\ne"),
        ("|one\ntwo", "dii", "|"),
        ("  x\n|\n  y", "dii", "  x\n|"),
        ("|", "dii", "|"),
        ("a\n  b|\n", "dij", "|"),
        ("a\n  b|\n  c", "cijZ<Esc>", "|Z\n"),
        ("x\n  a|\n  b\ny", "viid", "x\n|y"),
        ("x\n  a|\n  b\ny", "ciiZ<Esc>", "x\n|Z\n\ny"),
        ("x\n  a|\n  b\ny", "yiiGp", "x\n  a\n  b\ny\n  |a\n  b"),
        ("x\n  a|\n  b", "dii", "|x"),
        ("x\n  a|\n  b\ny", "viiy", "x\n|  a\n  b\ny"),
        ("x\n  a|\n  b\ny", "yiijp", "x\n  a\n  b\n  |a\n  b\ny"),
        ("x\n  a|\n  b", "ciiZ<Esc>", "x\n|Z"),
        ("x\n  a|\n  b\ny", "d2ii", "x\n|\ny"),
        ("x\n  a|\n\n  b\ny", "dai", "x\n|\ny"),
        ("x\n  a|\n  b\n\ny", "dai", "x\n|\ny"),
        ("x\n\tb|\n    c\ny", "gUii", "x\n|\tB\n    c\ny"),
        ("x\n    b|\n\tc\ny", "gUii", "x\n|    B\n\tC\ny"),
        ("x\n  \tb|\n\tc\ny", "gUii", "x\n|  \tB\n\tC\ny"),
    ])
    func indent(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }
}
