import Testing
@testable import OpenShelf

/// Text objects, ".", registers and visual p. Same notation as
/// VimEngineTests; every expected result was checked against `vim --clean`.
struct VimTextObjectTests {
    static func run(_ start: String, _ keys: String) -> String {
        VimEngineTests.marked(VimEngineTests.run(start, keys))
    }

    @Test(arguments: [
        // Words.
        ("foo b|ar baz", "diw", "foo | baz"),
        ("foo b|ar baz", "daw", "foo |baz"),
        ("foo bar b|az", "daw", "foo ba|r"),
        ("foo |  bar", "daw", "fo|o"),
        ("foo |  bar", "diw", "foo|bar"),
        ("a.b|.c d", "diW", "| d"),
        ("a.b|.c d", "daW", "|d"),
        ("one tw|o three four", "d2aw", "one |four"),
        ("one tw|o three four", "d3iw", "one | four"),
        ("one tw|o three", "ciwX<Esc>", "one |X three"),
        ("foo b|ar baz", "gUiw", "foo |BAR baz"),
        // Quotes: on the line, around the cursor or the next pair after it.
        ("say \"hel|lo\" now", "di\"", "say \"|\" now"),
        ("say \"hel|lo\" now", "da\"", "say |now"),
        ("|say \"hello\" now", "di\"", "say \"|\" now"),
        ("say |\"hello\" now", "ci\"X<Esc>", "say \"|X\" now"),
        ("a \"b\" c \"d|\" e", "di\"", "a \"b\" c \"|\" e"),
        ("a \"|b\" c", "ci\"X<Esc>", "a \"|X\" c"),
        ("a \"b|\" \"c\"", "da\"", "a |\"c\""),
        // No blanks after the closing quote: a" takes the ones before.
        ("say \"hell|o\"", "da\"", "sa|y"),
        ("say \"hello\" no|w", "di\"", "say \"hello\" no|w"),
        ("say \"a\\\"|b\" c", "di\"", "say \"|\" c"),
        ("it's 'o|k' yes", "di'", "it's '|' yes"),
        ("x `y|y` z", "da`", "x |z"),
        // Brackets: nested, counts, the cursor on a bracket, empty pairs.
        ("f(a, (b|, c), d)", "di(", "f(a, (|), d)"),
        ("f(a, (b|, c), d)", "da(", "f(a, |, d)"),
        ("f(a, (b|, c), d)", "d2i(", "f(|)"),
        ("f|(a, b)", "dib", "f(|)"),
        ("f(a, b|)", "dab", "|f"),
        ("x [1, |2] y", "di[", "x [|] y"),
        ("x {a |b} y", "diB", "x {|} y"),
        ("x {a |b} y", "daB", "x | y"),
        ("<a|b>", "di<", "<|>"),
        ("<a|b>", "da>", "|"),
        ("f(|)", "ci(X<Esc>", "f(|X)"),
        ("f() |x", "di(", "f() |x"),
        // Not inside a pair: the next one after the cursor.
        ("x |a (b) c", "di(", "x a (|) c"),
        ("f(a|b)", "yi(P", "f(a|bab)"),
        // Brackets on their own lines: i{ is the lines between.
        ("if {\n  a|\n  b\n}", "di{", "if {\n|}"),
        ("if {\n  a|\n  b\n}", "ci{X<Esc>", "if {\n  |X\n}"),
        // Paragraphs.
        ("a\nb|\n\nc\nd", "dip", "|\nc\nd"),
        ("a\nb|\n\nc\nd", "dap", "|c\nd"),
        ("a\n\nc|\nd", "dap", "|a"),
        ("a\nb|\n\nc", "yipP", "|a\nb\na\nb\n\nc"),
        ("a\n|\n\nc", "dip", "a\n|c"),
        ("|a\nb", ">ip", "    |a\n    b"),
        // Tags.
        ("x <a>he|llo</a> y", "dit", "x <a>|</a> y"),
        ("x <a>he|llo</a> y", "dat", "x | y"),
        ("<a><b>x|</b></a>", "d2it", "<a>|</a>"),
        ("<a>x</|a>", "dit", "<a>|</a>"),
        ("<|div class=\"c\">hi</div>", "cit!<Esc>", "<div class=\"c\">|!</div>"),
        ("<a>x<br/>|y</a>", "dit", "<a>|</a>"),
        ("<a>x<a/>|y</a>", "dit", "<a>|</a>"),
        ("<p>a<p>b|</p>c</p>", "dit", "<p>a<p>|</p>c</p>"),
        // In visual mode a text object selects.
        ("foo b|ar baz", "viwd", "foo | baz"),
        ("say \"hel|lo\" now", "va\"d", "say |now"),
        ("f(a, (b|, c))", "vi(d", "f(a, (|))"),
        ("a\nb|\n\nc", "vipd", "|\nc"),
    ])
    func textObjects(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    @Test(arguments: [
        ("|a b c d", "dw.", "|c d"),
        ("|a b c d", "dw2.", "|d"),
        ("a|bcdef", "x..", "a|ef"),
        ("|one\ntwo\nthree", "dd.", "|three"),
        ("|foo bar", "ciwX<Esc>w.", "X |X"),
        ("|a\nb\nc", "A;<Esc>j.j.", "a;\nb;\nc|;"),
        ("|a\nb", "ox<Esc>.", "a\nx\n|x\nb"),
        ("|aa bb", "cwZ<Esc>w.", "Z |Z"),
        ("|x", "rY.", "|Y"),
        // A yank is not a change: "." still repeats the delete.
        ("|a\nb\nc", "ddyy.", "|c"),
        ("|a b c", "dwyw.", "|c"),
        // A count repeats what an insert typed, and "." takes a new count.
        ("|ab", "3ix<Esc>", "xx|xab"),
        ("a|b", "2aXY<Esc>", "abXYX|Y"),
        ("|ab", "ix<Esc>3.", "xx|xxab"),
        ("say \"a (|b) c\"", "A!<Esc>2.", "say \"a (b) c\"!!|!"),
    ])
    func dotRepeats(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    @Test(arguments: [
        ("|one two", "\"ayiww\"byiw\"aP", "one on|etwo"),
        ("|one two", "\"ayiw\"Ayiw\"ap", "ooneon|ene two"),
        ("|one\ntwo", "\"_ddp", "|two"),
        ("|one two", "yiwwdiw\"0P", "oneon|e "),
        ("|a b", "yiwwviwp", "a |a"),
        ("|a b", "yiwwviwpu", "a |b"),
        ("|one\ntwo", "yyjVp", "one\n|one"),
        ("|one\ntwo\nthree", "yyjVjp", "one\n|one"),
    ])
    func registersAndVisualPut(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// "+ and "* are the system clipboard.
    @Test func plusRegisterIsTheClipboard() {
        nonisolated(unsafe) var board: String? = "pasted"
        var engine = VimEngineTests.engine("|ab")
        engine.clipboard = VimClipboard(read: { board }, write: { board = $0 })
        _ = engine.handle(VimEngineTests.keys("\"+P"))
        #expect(engine.string == "pastedab")
        _ = engine.handle(VimEngineTests.keys("0\"+yiw"))
        #expect(board == "pastedab")
        #expect(engine.register.text == "pastedab")
    }
}
