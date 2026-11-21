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
        ("x\n\tb|\n    c\ny", "gUii", "x\n|\tB\n    C\ny"),
        ("x\n    b|\n\tc\ny", "gUii", "x\n|    B\n\tC\ny"),
        ("x\n  \tb|\n\tc\ny", "gUii", "x\n|  \tB\n\tC\ny"),
        ("x\n  |a\n  b\ny", "<ii", "x\n|a\nb\ny"),
    ])
    func indent(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// ia / aa, evil-args (C18).
    @Test(arguments: [
        ("foo(a, b|b, c)", "dia", "foo(a, |, c)"),
        ("foo(a, b|b, c)", "daa", "foo(a, |c)"),
        ("foo(a|a, bb, c)", "dia", "foo(|, bb, c)"),
        ("foo(a|a, bb, c)", "daa", "foo(|bb, c)"),
        ("foo(a, bb, c|c)", "dia", "foo(a, bb, |)"),
        ("foo(a, bb, c|c)", "daa", "foo(a, bb|)"),
        ("f(x, g(y, z|), w)", "dia", "f(x, g(y, |), w)"),
        ("f(x, g(y, z|), w)", "daa", "f(x, g(y|), w)"),
        ("f(x, g(y|, z), w)", "dia", "f(x, g(|, z), w)"),
        ("f(x, g(y|, z), w)", "daa", "f(x, g(|z), w)"),
        ("f(|x)", "dia", "f(|)"),
        ("f(|x)", "daa", "f(|)"),
        ("f(a,b|,c)", "dia", "f(a,|,c)"),
        ("f(a,b|,c)", "daa", "f(a,|c)"),
        ("f(a ,b| , c)", "dia", "f(a ,|, c)"),
        ("f(a ,b| , c)", "daa", "f(a ,|c)"),
        ("call(one,\n     tw|o,\n     three)", "dia", "call(one,\n     |,\n     three)"),
        ("call(one,\n     tw|o,\n     three)", "daa", "call(one,\n     |three)"),
        ("call(\n  one,\n  tw|o\n)", "dia", "call(\n  one,\n  |)"),
        ("call(\n  one,\n  tw|o\n)", "daa", "call(\n  one|)"),
        ("[1, 2|2, 3]", "dia", "[1, |, 3]"),
        ("[1, 2|2, 3]", "daa", "[1, |3]"),
        ("{a: 1, b|: 2}", "dia", "{a: 1, |}"),
        ("{a: 1, b|: 2}", "daa", "{a: 1|}"),
        ("(defn f [x y|]\n  (+ x y))", "dia", "(defn f [|]\n  (+ x y))"),
        ("(defn f [x y|]\n  (+ x y))", "daa", "(defn f [|]\n  (+ x y))"),
        ("(foo a b|)", "dia", "(|)"),
        ("(foo a b|)", "daa", "(|)"),
        ("f(a, \"b, c|\", d)", "dia", "f(a, \"b, |, d)"),
        ("f(a, \"b, c|\", d)", "daa", "f(a, \"b, |d)"),
        ("foo ba|r", "dia", "|f"),
        ("foo ba|r", "daa", "foo ba|r"),
        ("f(a, [1, 2], b|)", "dia", "f(a, [1, 2], |)"),
        ("f(a, [1, 2], b|)", "daa", "f(a, [1, 2]|)"),
        ("f(a|, [1, 2], b)", "dia", "f(|, [1, 2], b)"),
        ("f(a|, [1, 2], b)", "daa", "f(|[1, 2], b)"),
        ("f( a|, b )", "dia", "f( |, b )"),
        ("f( a|, b )", "daa", "f( |b )"),
        ("foo(a|a, bb, c)", "d2ia", "foo(|, c)"),
        ("foo(a|a, bb, c)", "d2aa", "foo(|c)"),
        ("foo(a, b|b, c)", "ciaX<Esc>", "foo(a, |X, c)"),
        ("foo(a, b|b, c)", "vaad", "foo(a, |c)"),
        ("foo ba|r\nmore", "daa", "|\nmore"),
        ("x = f(a, b); y|\nz", "daa", "x = f(a, b|)\nz"),
        ("x\nfoo ba|r", "dia", "x\n|"),
    ])
    func argument(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// iu / au, Doom's URL object (C23).
    @Test(arguments: [
        ("see https://ex|ample.com/a/b?x=1#top now", "diu", "see https://|#top now"),
        ("see https://ex|ample.com/a/b?x=1#top now", "dau", "see | now"),
        ("see https://example.com/a|/b.", "diu", "see https://|."),
        ("see https://example.com/a|/b.", "dau", "see |."),
        ("(https://ex|ample.com/x)", "diu", "(https://|)"),
        ("(https://ex|ample.com/x)", "dau", "(|)"),
        ("go to www.ex|ample.com/p, ok", "diu", "go to www.ex|ample.com/p, ok"),
        ("go to www.ex|ample.com/p, ok", "dau", "go to www.ex|ample.com/p, ok"),
        ("\"http://a.b/c|\"", "diu", "\"http://|\""),
        ("\"http://a.b/c|\"", "dau", "\"|\""),
        ("x ftp://h|ost/f y", "diu", "x ftp://| y"),
        ("x ftp://h|ost/f y", "dau", "x | y"),
        ("mailto:me@ex|ample.com", "diu", "mailto:me@ex|ample.com"),
        ("mailto:me@ex|ample.com", "dau", "|"),
        ("no url he|re", "diu", "no url he|re"),
        ("no url he|re", "dau", "no url he|re"),
        ("|https://a.b/c d", "diu", "https://| d"),
        ("|https://a.b/c d", "dau", "| d"),
        ("a <https://x|.y/z> b", "diu", "a <https://|> b"),
        ("a <https://x|.y/z> b", "dau", "a <|> b"),
        ("url: https://ex|ample.com/a#frag", "diu", "url: https://|#frag"),
        ("url: https://ex|ample.com/a#frag", "dau", "url:| "),
        ("file:///Us|ers/x.txt", "diu", "file:/|/"),
        ("file:///Us|ers/x.txt", "dau", "|"),
        ("https://a.b/p?q=1&r=|2 x", "diu", "https://|?q=1&r=2 x"),
        ("https://a.b/p?q=1&r=|2 x", "dau", "| x"),
        ("see https://ex|ample.com/a now", "ciuX<Esc>", "see https://|X now"),
        ("see https://ex|ample.com/a now", "viud", "see https://| now"),
        ("see https://ex|ample.com/a now", "vaud", "see | now"),
        ("see https://a.b/c| now", "diu", "see https://| now"),
        ("x https://a.b/c, |y", "dau", "x https://a.b/c, |y"),
        ("x (https://a.b/c)| y", "dau", "x (https://a.b/c)| y"),
        ("see https://a.b/c|; x", "dau", "see |; x"),
        ("x https://a.b/c;| y", "dau", "x | y"),
        ("see https://a.b/c.| now", "dau", "see | now"),
    ])
    func url(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// ix / ax, exato's XML attribute (C23).
    @Test(arguments: [
        ("<a hr|ef=\"x.html\" class=\"b\">", "dix", "<a | class=\"b\">"),
        ("<a hr|ef=\"x.html\" class=\"b\">", "dax", "<a| class=\"b\">"),
        ("<a href=\"x.h|tml\" class=\"b\">", "dix", "<a | class=\"b\">"),
        ("<a href=\"x.h|tml\" class=\"b\">", "dax", "<a| class=\"b\">"),
        ("<a href=\"x.html\" cl|ass=\"b\">", "dix", "<a href=\"x.html\" |>"),
        ("<a href=\"x.html\" cl|ass=\"b\">", "dax", "<a href=\"x.html\"|>"),
        ("<a hr|ef=x class=b>", "dix", "<a | class=b>"),
        ("<a hr|ef=x class=b>", "dax", "<a| class=b>"),
        ("<a href=x|y class=b>", "dix", "<a | class=b>"),
        ("<a href=x|y class=b>", "dax", "<a| class=b>"),
        ("<a |href=\"x\">", "dix", "<a |>"),
        ("<a |href=\"x\">", "dax", "<a|>"),
        ("<a| href=\"x\">", "dix", "<a |>"),
        ("<a| href=\"x\">", "dax", "<a|>"),
        ("<div id=\"a\">te|xt</div>", "dix", "<div id=\"a\">te|xt</div>"),
        ("<div id=\"a\">te|xt</div>", "dax", "<div id=\"a\">te|xt</div>"),
        ("<input dis|abled value=\"v\">", "dix", "<input disabled |>"),
        ("<input dis|abled value=\"v\">", "dax", "<input disabled|>"),
        ("<a\n  hr|ef=\"x\">", "dix", "<a\n  |>"),
        ("<a\n  hr|ef=\"x\">", "dax", "<a\n |>"),
        ("<img src=\"a b|.png\" alt=\"c\">", "dix", "<img | alt=\"c\">"),
        ("<img src=\"a b|.png\" alt=\"c\">", "dax", "<img| alt=\"c\">"),
        ("no| attrs", "dix", "no| attrs"),
        ("no| attrs", "dax", "no| attrs"),
        ("<a data-x|=\"1\">", "dix", "<a |>"),
        ("<a data-x|=\"1\">", "dax", "<a|>"),
        ("<a href=\"x.h|tml\" class=\"b\">", "cixX<Esc>", "<a |X class=\"b\">"),
        ("<a href=\"x.h|tml\" class=\"b\">", "vaxd", "<a| class=\"b\">"),
        ("<a| b=1 c=\"2\">", "dix", "<a b=1 |>"),
        ("<a |b=1 c=\"2\">", "dix", "<a b=1 |>"),
    ])
    func xml(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// ysiwf and ⌃F, dsf, csf (C16; evil-surround and embrace).
    @Test(arguments: [
        ("x = ba|r + 1", "ysiwffoo<CR>", "x = |foo(bar) + 1"),
        ("x = ba|r + 1", "ysiw<C-f>foo<CR>", "x = |(foo bar) + 1"),
        ("(a |b)", "ysiw<C-f>inc<CR>", "(a |(inc b))"),
        ("foo(ba|r)", "dsf", "ba|r"),
        ("(inc (dec x|))", "ds<C-f>", "(inc x|)"),
        ("a |b c", "viwSfg<CR>", "a |g(b) c"),
        ("a b|c d", "ysiwf<CR>", "a |(bc) d"),
        ("a b| c", "yssff<CR>", "|f(a b c)"),
        ("a.b(c|)", "dsf", "a.|c"),
        ("foo(a, (b|))", "dsf", "a, (b|)"),
        ("foo (ba|r)", "dsf", "foo (ba|r)"),
        ("foo-bar(x|)", "dsf", "|x"),
        ("x = |bar + 1", "ys2wfg<CR>", "x = |g(bar +) 1"),
        ("x foo(ba|r) y", "csf)", "x |(bar) y"),
        ("x (foo ba|r) y", "cs<C-f>]", "x |[bar] y"),
        ("x foo(ba|r) y", "cs)fg<CR>", "x foo|g(bar) y"),
        ("(defn f [x]\n  (+ x| 1))", "ysa(<C-f>inc<CR>", "(defn f [x]\n  |(inc (+ x 1)))"),
        ("a b|c d", "ysiwfab<BS>c<CR>", "a |ac(bc) d"),
        ("f(|x)", "dsf", "|x"),
        ("|f(x)", "dsf", "|f(x)"),
        ("(a (b c|))", "ds<C-f>", "(a c|)"),
        ("a foo|(x)", "dsf", "a |x"),
        ("fo|o(x)", "dsf", "fo|o(x)"),
    ])
    func functionSurround(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// iB / aB, Doom's anyblock over ( { [ < (C24).
    @Test(arguments: [
        ("(a [b| c] d)", "diB", "(a [|] d)"),
        ("(a [b| c] d)", "daB", "(a | d)"),
        ("{:a (f x|) :b 2}", "ciBX<Esc>", "{:a (|X) :b 2}"),
        ("{:a (f x) :b |2}", "diB", "{|}"),
        ("f(a, \"b|\")", "diB", "f(|)"),
        ("x |(a b)", "diB", "x (|)"),
        ("x| y", "diB", "x| y"),
        ("(a\n  b|\n  c)", "diB", "(|)"),
        ("(defn f [x]\n  (let [a 1\n        b| 2]\n    (+ a b)))", "diB", "(defn f [x]\n  (let [|]\n    (+ a b)))"),
        ("(a (b| c))", "d2iB", "(|)"),
        ("<a (b|)>", "diB", "<a (|)>"),
        ("if (x) {\n  y|;\n}", "diB", "if (x) {\n|}"),
        ("(a |[b] c)", "diB", "(a [|] c)"),
        ("(a [b]| c)", "diB", "(|)"),
        ("(a [b] |c)", "vaBd", "|"),
        ("x {a |b} y", "diB", "x {|} y"),
        ("x {a |b} y", "daB", "x | y"),
        ("{:a [1 |2]}", "ciBX<Esc>", "{:a [|X]}"),
        ("(a <b|> c)", "daB", "(a | c)"),
        ("(a {b} |c)", "diB", "(|)"),
        ("x |y (a)", "daB", "x y| "),
        ("|", "diB", "|"),
        ("(a\n  (b|)\n  c)", "2diB", "(|)"),
        ("(defn f [x]\n  (let [a 1\n        b| 2]\n    (+ a b)))", "2diB", "(defn f [x]\n  (let [|]\n    (+ a b)))"),
        ("(defn f [x]\n  (let [a 1\n        b| 2]\n    (+ a b)))", "ciBX<Esc>", "(defn f [x]\n  (let [|X]\n    (+ a b)))"),
        ("{|}", "ciBX<Esc>", "{|X}"),
        ("(a [b (c|)])", "9diB", "(a [|])"),
        ("(a [b (|c)])", "9diB", "(a [|])"),
        ("(a [b (|c)])", "3diB", "(a [|])"),
    ])
    func anyBlock(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// gc, evil-nerd-commenter, each in the mode its comment string guesses (C25).
    @Test(arguments: [
        ("(defn f [x]\n  |(inc x))", "gcc", "(defn f [x]\n  |;; (inc x))"),
        ("(defn f [x]\n  |(inc x))", "gcip", "|;; (defn f [x]\n;;   (inc x))"),
        ("|(a)\n(b)\n(c)", "gcj", "|;; (a)\n;; (b)\n(c)"),
        ("|(a)\n(b)", "Vjgc", "|;; (a)\n;; (b)"),
        ("(a)\n|;; (b)\n(c)", "gcc", "(a)\n|(b)\n(c)"),
        ("|;; (a)\n;; (b)", "gcip", "|(a)\n(b)"),
        ("|(a)\n;; (b)", "gcip", "|;; (a)\n;; ;; (b)"),
        ("  |(a)\n\n  (b)", "gcG", "  |;; (a)\n\n  ;; (b)"),
        ("|(a) ; tail", "gcc", "|;; (a) ; tail"),
        ("|var x = 1;\nvar y;", "gcc", "|// var x = 1;\nvar y;"),
        ("|var x = 1;\nvar y;", "gcj", "|// var x = 1;\n// var y;"),
        ("|x = 1\ny = 2", "gcj", "|# x = 1\n# y = 2"),
        ("|echo a", "gcc", "|# echo a"),
        ("|select 1;\nselect 2;", "gcj", "|-- select 1;\n-- select 2;"),
        ("|(a)", "3gcc", "|;; (a)"),
        ("|(a)\n(b)\n(c)", "2gcc", "|;; (a)\n;; (b)\n(c)"),
        ("|(a)", "gcc.", "|(a)"),
        ("|(a)", "gccu", "|(a)"),
        ("|  ;; x", "gcc", "  |x"),
        ("|a\n  b", "gcj", "|# a\n#   b"),
        ("|;;   x", "gcc", "  |x"),
        ("|;x", "gcc", "|x"),
        ("|;; x\n\n;; y", "gcG", "|x\n\ny"),
        ("|  ;; a\n    ;; b", "gcj", "  |a\n    b"),
        ("|;;x", "gcc", "|x"),
        ("|#x", "gcc", "|x"),
        ("|# x\n#y", "gcj", "|x\ny"),
        ("|// x", "gcc", "|x"),
        ("|-- x", "gcc", "|x"),
        ("|\n", "gcc", "|\n"),
        ("|(a)\n  \n(b)", "gcG", "|;; (a)\n  \n;; (b)"),
        ("|;;; x", "gcc", "|x"),
        ("|(a)\n(b)", "gc}", "|;; (a)\n;; (b)"),
    ])
    func comment(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// ic / ac, evil-nerd-commenter (C22).
    @Test(arguments: [
        ("(a)\n;; x|y\n;; z\n(b)", "dic", "(a)\n;; |y\n;; \n(b)"),
        ("(a)\n;; x|y\n;; z\n(b)", "dac", "(a)\n(b|)"),
        ("(a) ; tai|l", "dic", "(a) ;| "),
        ("(a) ; tai|l", "dac", "(a) |l"),
        ("(a)\n  ;; x|y\n(b)", "dic", "(a)\n  ;;| \n(b)"),
        ("(a)\n  ;; x|y\n(b)", "dac", "(a)\n | \n(b)"),
        ("x // co|mment\ny", "dic", "x //| \ny"),
        ("x // co|mment\ny", "dac", "x| \ny"),
        ("(a)\n;; x|y\n;; z\n(b)", "vicd", "(a)\n;; |y\n;; \n(b)"),
        ("(a)\n;; x|y\n;; z\n(b)", "cicQ<Esc>", "(a)\n;; |Qy\n;; Q\n(b)"),
        ("(a) ; tai|l\n(b)", "dac", "(a)| \n(b)"),
        ("(a) ; tai|l\n(b)", "dic", "(a) ;| \n(b)"),
        ("(a)\n;; x|y\n(b)", "dac", "(a)\n|\n(b)"),
        ("(a)\n;; x|y\n;; z\n(b)", "dac", "(a)\n(b|)"),
        ("(a)\n  ;; x|y\n  ;; z\n(b)", "dac", "(a)\n(b|)"),
        ("(a)\n;; x|y\n;; zzz\n(b)", "dic", "(a)\n;;| \n;; \n(b)"),
        ("(a)\n;; xxx|y\n;; z\n(b)", "dic", "(a)\n;; |xxy\n;; \n(b)"),
        ("(a)\n  ;; x|y\n  ;; z\n(b)", "dic", "(a)\n  ;; |y\n  ;; \n(b)"),
        ("(a) |; tail\n(b)", "dic", "(a) ;| \n(b)"),
        ("(a|) ; tail\n(b)", "dic", "(a) ;| \n(b)"),
        ("x // a|b\ny", "dac", "x| \ny"),
        ("(a)\n;; x|y\n\n;; z\n(b)", "dac", "(a)\n|\n\n;; z\n(b)"),
        ("(a)\n|(b)", "dic", "(a)\n|(b)"),
        ("(a)\n;;   x|y\n;; z\n(b)", "dic", "(a)\n;; | xy\n;; \n(b)"),
        ("(a)\n;; x|y\n;;   zz\n(b)", "dic", "(a)\n;;| \n;; \n(b)"),
    ])
    func commentObject(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// visual ⌃A ⌃X and g⌃A g⌃X, evil-numbers (C29).
    @Test(arguments: [
        ("|0\n0\n0", "VGg<C-a>", "|1\n2\n3"),
        ("|1\n1\n1", "VG2g<C-a>", "|3\n5\n7"),
        ("|x 5\nx 5\nx 5", "VGg<C-x>", "|x 4\nx 3\nx 2"),
        ("|0\nnone\n0", "VGg<C-a>", "|1\nnone\n2"),
        ("|a1 b1\na1 b1", "VGg<C-a>", "|a2 b3\na4 b5"),
        ("|0 0\n0 0", "vjg<C-a>", "|1 2\n3 0"),
        ("|0\n0\n0", "VG<C-a>", "|1\n1\n1"),
        ("|0x0f\n0x0f", "VGg<C-a>", "|0x10\n0x11"),
        ("|-1\n-1\n-1", "VGg<C-a>", "|0\n1\n2"),
        ("|007\n007", "VGg<C-a>", "|008\n009"),
        ("|5\n5\n5", "VG3<C-a>", "|8\n8\n8"),
        ("x |1 1 1", "v$g<C-a>", "x |2 3 4"),
        ("|0\n0\n0", "VGg<C-a>gvg<C-a>", "|2\n4\n6"),
    ])
    func visualNumbers(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// visual * and #, evil-visualstar (C30).
    @Test(arguments: [
        ("|foo bar foo.bar foo", "viw*", "foo bar |foo.bar foo"),
        ("|foo bar foo.bar foo", "vee*", "|foo bar foo.bar foo"),
        ("foo bar foo.bar |foo", "viw#", "foo bar foo.bar |foo"),
        ("|a.b x a.b", "v2l*", "a.b x |a.b"),
        ("|ab abc ab", "viw*", "ab |abc ab"),
        ("|ab abc ab", "viw*n", "ab abc |ab"),
        ("|Foo foo FOO", "viw*", "|Foo foo FOO"),
        ("|a\nb a\nb", "vj*", "a\nb |a\nb"),
        ("|ab x ab", "viw*N", "|ab x ab"),
        ("|a*b c a*b", "v2l*", "a*b c |a*b"),
        ("foo bar foo.bar |foo", "viw#n", "foo bar |foo.bar foo"),
        ("foo bar foo.bar |foo", "viwo#", "foo bar |foo.bar foo"),
        ("foo x |foo y", "viw#", "foo x |foo y"),
        ("|foo x foo y", "viw#", "|foo x foo y"),
        ("foo x f|oo y", "viw#", "foo x |foo y"),
        ("foo x foo |foo", "viw*", "|foo x foo foo"),
    ])
    func visualStar(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// gl and gL, evil-lion (C28).
    @Test(arguments: [
        ("|a = 1\nbbb = 2\ncc = 3", "glip=", "|a   = 1\nbbb = 2\ncc  = 3"),
        ("|a = 1\nbbb = 2\ncc = 3", "gLip=", "|a =   1\nbbb = 2\ncc =  3"),
        ("|a, b, c\nlong, x, yy\nm, n, o", "glip,", "|a   , b, c\nlong, x, yy\nm   , n, o"),
        ("|a, b, c\nlong, x, yy\nm, n, o", "gLip,", "|a,    b, c\nlong, x, yy\nm,    n, o"),
        ("|a, b, c\nlong, x, yy\nm, n, o", "1glip,", "|a   , b, c\nlong, x, yy\nm   , n, o"),
        ("|a, b, c\nlong, x, yy\nm, n, o", "1gLip,", "|a,    b, c\nlong, x, yy\nm,    n, o"),
        ("|  x  = 1\n  long = 2", "glip=", "|  x    = 1\n  long = 2"),
        ("|a = 1\nbbb = 2\ncc = 3", "Vjjgl=", "|a   = 1\nbbb = 2\ncc  = 3"),
        ("|a = 1\nbbb = 2\ncc = 3", "gl2j=", "|a   = 1\nbbb = 2\ncc  = 3"),
        ("|a := 1\nbbb := 2", "glip:", "|a   := 1\nbbb := 2"),
        ("|a := 1\nbbb := 2", "glip=", "|a :  = 1\nbbb := 2"),
        ("|a=1\nbb=2", "glip=", "|a =1\nbb=2"),
        ("|a = 1\n\nbbb = 2", "glG=", "|a   = 1\n\nbbb = 2"),
        ("a = 1\n|bbb    = 2", "glip=", "a   = 1\n|bbb = 2"),
        ("|x\ny", "glip=", "|x\ny"),
        ("|a = 1\nbbb = 2\ncc = 3", "glip/=<CR>", "|a   = 1\nbbb = 2\ncc  = 3"),
        ("|a, b, c\nlong, x,   yy\nm, nnnn, o", "glip,", "|a   , b   , c\nlong, x   ,   yy\nm   , nnnn, o"),
        ("|a, b, c\nlong, x,   yy\nm, nnnn, o", "gLip,", "|a,    b,    c\nlong, x,    yy\nm,    nnnn, o"),
        ("|x = 1\ny  =  2", "gLip=", "|x =  1\ny  = 2"),
        ("|a=1\nbb=2", "2glip=", "|a=1\nbb=2"),
        ("|a = 1\nbbb = 2", "glj=u", "|a = 1\nbbb = 2"),
        ("|aaa  = 1\nb = 2", "glip=", "|aaa = 1\nb   = 2"),
        ("|a, bbb, c\nlong, x, yy", "1glip,", "|a   , bbb, c\nlong, x, yy"),
        ("|a, bbb, c\nlong, x, yy", "glip,", "|a   , bbb, c\nlong, x  , yy"),
        ("|a =  1\nbbb = 2", "gLip=", "|a =   1\nbbb = 2"),
    ])
    func align(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// gx and gX, evil-exchange (C27).
    @Test(arguments: [
        ("|one two three", "gxiwwgxiw", "two |one three"),
        ("|one two three", "gxiwwwgxiw", "three two |one"),
        ("|one two three", "gxiwgX", "|one two three"),
        ("|one two three", "gxiwwgXgxiw", "one |two three"),
        ("|one two three", "viwgxwviwgx", "two |one three"),
        ("|a b", "gxiwgxiw", "|a b"),
        ("|one two three", "gxawwgxaw", "|two one three"),
        ("|ab cd", "gx2lwgx2l", "cd |ab"),
        ("|one two three four", "gxe2wgxe", "three two |one four"),
        ("|abc", "gxlgxl", "|abc"),
        ("|one two three", "gxiw3wgxiw", "three two |one"),
        ("|one\ntwo\nthree\nfour", "gxxjjgxx", "three\ntwo\n|one\nfour"),
        ("  |one\ntwo\nthree x\nfour", "gxxjjgxx", "three x\ntwo\n  |one\nfour"),
        ("|a b c", "gxiwwviwgx", "b |a c"),
        ("|one two\nthree four", "gxjjgxx", "|one two\nthree four"),
    ])
    func exchange(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// s S, z Z x X after an operator, and f t F T as evil-snipe with Doom's settings (C26). One emacs per case.
    @Test(arguments: [
        ("|one two three tw4", "stw", "one |two three tw4"),
        ("|one two three tw4", "stw;", "one two three |tw4"),
        ("one two three t|w4", "Stw", "one |two three tw4"),
        ("|a.b a.b", "s.b", "a|.b a.b"),
        ("|aXb axb", "sxb", "a|Xb axb"),
        ("|aXb axb", "sXb", "a|Xb axb"),
        ("|ab\ncd", "scd", "|ab\ncd"),
        ("|one two three", "dztw", "|o three"),
        ("|one two three", "dZtw", "|one two three"),
        ("|one two three", "vstwd", "|o three"),
        ("one tw|o three", "Stw", "one |two three"),
        ("|a b c b d b", "fb", "a |b c b d b"),
        ("|a b c b d b", "tb", "a| b c b d b"),
        ("a b c b d |b", "Fb", "a b c |b d b"),
        ("|aB ab", "fb", "a|B ab"),
        ("|a b c b d b", "2fb", "a b c |b d b"),
        ("|a b c b d b", "dfb", "| c b d b"),
        ("|a b c b d b", "dfbf", "| c b d b"),
        ("|a b c b d b", "d2fb", "| d b"),
        ("|one two", "s", "|one two"),
        ("|one two", "sZZ", "|one two"),
        ("|café cafe", "sfe", "ca|fé cafe"),
        ("|abab", "sab", "ab|ab"),
        ("|a,b,c", "dt,", "|,c"),
        ("a,b,|c", "T,", "a,|b,c"),
        ("|a,b,c", "2f,,", "a,b|,c"),
        ("|a,b,c,d", "f,;", "a,b|,c,d"),
        ("|a,b,c,d", "2f,;", "a,b|,c,d"),
        ("|a b c b", "dtb", "|b c b"),
        ("|abc", "sbc", "a|bc"),
        ("|abc abc", "dzbc", "| abc"),
        ("|abc abc", "dxbc", "|bc"),
        ("abc |abc", "dZab", "|abc"),
        ("abc |abc", "dXab", "ab|abc"),
        ("|one two\nthree two", "stw;", "one two\nthree |two"),
        ("|aa", "fa", "a|a"),
        ("|xa", "ta", "|xa"),
        ("|xab", "tb", "x|ab"),
        ("|one two", "s<CR>", "|one two"),
        ("|xAb ab", "sab", "x|Ab ab"),
        ("|xab Ab", "sAb", "xab |Ab"),
        ("|aB ab", "fB", "a|B ab"),
        ("|a b", "vfbd", "|"),
        ("|a bc", "vsbcd", "|"),
        ("|abc", "sb<CR>", "a|bc"),
        ("|a,b,c", "t,", "a,|b,c"),
        ("|aa,b,c", "t,", "a|a,b,c"),
        ("|aa,b,c", "t,;", "aa,|b,c"),
        ("a,b,|c", "F,", "a,b|,c"),
        ("|a,b,c", "fz", "|a,b,c"),
        ("|a,b,c", "f,;", "a,b|,c"),
    ])
    func snipe(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }
}
