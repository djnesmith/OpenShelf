import Testing
@testable import OpenShelf

/// vim-surround's ds, cs, ys, yss and visual S. Expected results come from
/// vim --clean with tpope/vim-surround loaded, and vim-repeat for ".".
struct VimSurroundTests {
    @Test(arguments: [
        // ds: the target's marks go; an opening bracket also takes the blanks inside.
        ("\"Hello |world!\"", "ds\"", "|Hello world!"),
        ("(123+4|*56)/2", "ds)", "|123+4*56/2"),
        ("( a|b )", "ds(", "|ab"),
        ("( a|b )", "ds)", "| ab "),
        ("<div>Yo!|</div>", "dst", "|Yo!"),
        ("(|a)", "ds(", "|a"),
        ("f(a, (b|, c))", "2ds(", "f|a, (b, c)"),
        ("f(|x)", "dsb", "f|x"),
        ("a [|b] c", "dsr", "a |b c"),
        // cs: target, then replacement.
        ("\"Hello |world!\"", "cs\"'", "|'Hello world!'"),
        ("\"Hello |world!\"", "cs\"<q>", "|<q>Hello world!</q>"),
        ("(123+4|*56)/2", "cs)]", "|[123+4*56]/2"),
        ("(123+4|*56)/2", "cs)[", "|[ 123+4*56 ]/2"),
        ("<div>Yo!|</div>", "cst<p>", "|<p>Yo!</p>"),
        ("say <a href=\"x\">|hi</a>", "cst<b>", "say |<b>hi</b>"),
        ("{ |a }", "cs{[", "|[ a ]"),
        ("f(|x)", "cs(b", "f|(x)"),
        ("a <|b> c", "csa)", "a |(b) c"),
        // ys with a motion or text object, and yss.
        ("Hello w|orld!", "ysiw)", "Hello |(world)!"),
        ("Hello w|orld!", "ysiw(", "Hello |( world )!"),
        ("if |x>3 {", "ysW(", "if |( x>3 ) {"),
        ("    Hello w|orld!", "yssB", "    |{Hello world!}"),
        ("|hello world", "ysw)", "|(hello) world"),
        ("|hello world", "yse\"", "|\"hello\" world"),
        ("say |hi", "ysiw<em>", "say |<em>hi</em>"),
        ("say |hi", "ysiwb", "say |(hi)"),
        ("say |hi", "ysiw]", "say |[hi]"),
        ("|x", "yss\"", "|\"x\""),
        ("x |hi y", "ysiw*", "x |*hi* y"),
        ("|one two", "ys2w\"", "|\"one two\""),
        ("|one two", "ys$)", "|(one two)"),
        ("x \"a|b\" y", "ysi\")", "x \"|(ab)\" y"),
        ("|x  ", "yss)", "|(x)  "),
        ("|a\nb\nc", "2yss)", "|(a\nb)\nc"),
        // ys over lines puts the pair on lines of its own, without indenting.
        ("|a\nb", "ysj)", "|(\na\nb\n)"),
        ("  |a\n  b", "ysip]", "|  [\n  a\n  b\n  ]"),
        // Visual S: characters, or lines on lines of their own, indented.
        ("my $str = |whee!;", "vllllS'", "my $str = |'whee!';"),
        ("x |a b y", "vlS\"", "x |\"a \"b y"),
        ("a|\nb", "VjS)", "|(\n    a\n    b\n)"),
        ("  a|\n  b", "VjS}", "|  {\n      a\n      b\n  }"),
    ])
    func surround(start: String, keys: String, expected: String) {
        #expect(VimTextObjectTests.run(start, keys) == expected)
    }

    /// "." repeats a surround, as repeat.vim makes it do.
    @Test(arguments: [
        ("|a b", "ysiw)W.", "(a) |(b)"),
        ("say \"|hi\" \"yo\"", "cs\"'w.", "say 'hi' |'yo'"),
        ("(a) |(b)", "ds)0.", "|a b"),
    ])
    func dotRepeatsSurround(start: String, keys: String, expected: String) {
        #expect(VimTextObjectTests.run(start, keys) == expected)
    }

    /// A tag can end with Return, and Backspace takes back a letter.
    @Test func tagsEndWithReturnAndTakeBackspace() {
        for keys in [VimEngineTests.keys("ysiw") + [.char("<"), .char("p"), .enter], VimEngineTests.keys("ysiw") + [.char("<"), .char("p"), .char("x"), .backspace, .char(">")]] {
            var engine = VimEngineTests.engine("a |b c")
            _ = engine.handle(keys)
            #expect(VimEngineTests.marked(engine) == "a |<p>b</p> c")
        }
    }

    @Test func unknownLettersAndEmptyTagsAreNotReplacements() {
        #expect(VimEngine.surroundPair("x").map { [$0.open, $0.close] } == ["x", "x"])
        #expect(VimEngine.surroundPair("<>") == nil)
        var engine = VimEngineTests.engine("|hi")
        _ = engine.handle(VimEngineTests.keys("ysiwq"))
        #expect(engine.string == "hi")
        #expect(engine.mode == .normal)
    }
}
