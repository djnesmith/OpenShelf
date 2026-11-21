import Testing
@testable import OpenShelf

/// Doom keys (ROADMAP C16-C43) where the check is the engine's own state, not one of evil's
/// results: undo steps and "." repeats.
struct VimDoomExtraTests {
    @Test func changeOnAnIndentBlockIsOneUndoStep() {
        // dd first, so a second undo step would show: uu must take back both changes.
        let engine = VimEngineTests.run("w\nx\n  |a\n  b\ny", "ggddjciiZ<Esc>uu")
        #expect(engine.string == "w\nx\n  a\n  b\ny")
    }

    @Test func deleteOnAnIndentBlockRepeatsWithDot() {
        let engine = VimEngineTests.run("x\n  |a\ny\n  b\nz", "diijj.")
        #expect(engine.string == "x\n\ny\n\nz")
    }

    /// "." types the same name again, as vim-surround with repeat.vim does. evil in
    /// `emacs --batch` asks again and gets no name ("(b)"); left as vim's, a known difference.
    @Test func functionSurroundRepeatsWithItsName() {
        let engine = VimEngineTests.run("|a b", "ysiwffoo<CR>fb.")
        #expect(engine.string == "foo(a) foo(b)")
    }

    /// ysii wraps as ysip does here (pair on lines of its own); Doom's evil-surround differs for
    /// both ("x\n(\na\nb)\n\ny"), left for David to decide.
    @Test func surroundOnAnIndentBlockIsLikeAParagraph() {
        #expect(VimEngineTests.run("x\n  |a\n  b\ny", "ysiib").string == "x\n  (\n  a\n  b\n  )\ny")
    }

    @Test func newObjectsSayWhyTheyFailed() {
        for (start, keys, hint) in [("x) |y", "dia", "dia: no argument here"), ("|x", "diu", "diu: no URL here"), ("|x", "dix", "dix: no attribute here"), ("|x", "dsf", "dsf: no function call around the cursor")] {
            #expect(VimEngineTests.run(start, keys).failureHint == hint)
        }
    }

    /// > on ii keeps the cursor's column, as Doom's does. (Doom also rounds the indent to a
    /// multiple of 4, evil-shift-round; the engine's > adds 4, as vim, for every motion.)
    @Test func shiftOnAnIndentBlockKeepsTheColumn() {
        #expect(VimEngineTests.marked(VimEngineTests.run("x\n  a|b\n  b\ny", ">ii")) == "x\n   |   ab\n      b\ny")
    }

    /// A huge count on iB takes each kind's outermost pair, then the smallest, as evil does,
    /// without trying every count down from 999999.
    @Test(.timeLimit(.minutes(1))) func hugeCountOnAnyBlockTakesTheOutermostPair() {
        #expect(VimEngineTests.run("(a [b (c|)])", "999999diB").string == "(a [])")
    }

    /// gc's comment string, guessed from the text (David, 2026-11-21: guess the mode; SQL gets --).
    @Test(arguments: [
        ("(defn f [x] x)", ";;"), ("; note\n(a)", ";;"), ("x = 1\n// old\n", "//"), ("x\n  # old", "#"), ("-- q\nselect 1", "--"),
        ("SELECT * FROM t", "--"), ("with a as (select 1)", "--"), ("Create table t", "--"), ("var x = 1;", "//"), ("if (a) {\n}", "//"),
        ("echo hi", "#"), ("x // note", "//"), ("see https://a.b", "#"), ("", "#"), ("   \n  ", "#"), ("selection = 2", "#"),
    ])
    func commentStringIsGuessedFromTheText(text: String, expected: String) {
        #expect(VimEngine.commentString(for: text) == expected)
    }

    @Test func commentIsOneUndoStep() {
        #expect(VimEngineTests.run("w\n|(a)\n(b)", "kddgcjuu").string == "w\n(a)\n(b)")
    }

    @Test func visualNumbersAreOneUndoStep() {
        #expect(VimEngineTests.run("w\n|0\n0", "kddVjg<C-a>uu").string == "w\n0\n0")
    }

    @Test func visualNumbersWithNoNumberChangeNothing() {
        let engine = VimEngineTests.run("|a b", "v$<C-a>")
        #expect(engine.string == "a b")
        #expect(engine.mode == .normal)
    }

    @Test func exchangeMarkIsShownUntilSwappedOrCancelled() {
        var engine = VimEngineTests.run("|one two", "gxiw")
        #expect(engine.exchangeHighlight == 0..<3)
        _ = engine.handle(VimEngineTests.keys("gX"))
        #expect(engine.exchangeHighlight == nil)
        _ = engine.handle(VimEngineTests.keys("gxiwwgxiw"))
        #expect(engine.exchangeHighlight == nil)
        #expect(engine.string == "two one")
    }

    @Test func aChangeBetweenDropsTheExchangeMark() {
        let engine = VimEngineTests.run("|one two", "gxiwwxbgxiw")
        #expect(engine.string == "one wo")
        #expect(engine.exchangeHighlight == 0..<3)
    }

    @Test func exchangeIsOneUndoStep() {
        #expect(VimEngineTests.run("|one two", "gxiwwgxiwu").string == "one two")
    }

    /// Right after a snipe its own key repeats it and its backward key goes back, as evil-snipe's
    /// transient keys do in Doom (emacs --batch can't show those keys, so these are by hand).
    @Test(arguments: [
        ("|ab ab ab", "sabs", "ab ab |ab"), ("|ab ab ab", "sabsS", "ab |ab ab"), ("|a b c b d b", "fbf", "a b c |b d b"),
        ("|a b c b d b", "fbff", "a b c b d |b"), // After F, f repeats it (back) and F reverses it, as evil-snipe's transient map binds f / F.
        ("a b c b d |b", "Fbf", "a |b c b d b"), ("a b c b d |b", "FbF", "a b c b d |b"), ("|a b c b d b", "tbt", "a b c| b d b"),
        // Any other key ends it: s after l starts a new snipe, waiting for its characters.
        ("|ab ab ab", "sabls", "ab a|b ab"),
        // s then Return repeats the last snipe.
        ("|ab ab ab", "sabls<CR>", "ab ab |ab"),
    ])
    func snipeRepeatKeys(start: String, keys: String, expected: String) {
        #expect(VimEngineTests.marked(VimEngineTests.run(start, keys)) == expected)
    }

    /// gxx is no change for ".", as gx{motion} isn't: "." still repeats the change before it.
    @Test func exchangeDoesNotReplaceTheLastChange() {
        #expect(VimEngineTests.run("|ab\ncd\nef", "xgxxj.").string == "b\nd\nef")
    }

    /// iw and aw on the empty line after a final line break (2026-11-21: viw there crashed the
    /// app). Expected results are evil's in emacs --batch with the cursor at the buffer's end,
    /// where the word is that last line break; G gets the cursor there.
    @Test(arguments: [
        ("|a\n", "GviwS)", "a|(\n)"),
        ("|a\n", "Gviwd", "|a"),
        ("|a\n", "Gdiw", "|a"),
        ("|a\n", "Gdaw", "|a"),
        ("|a\n", "GviWd", "|a"),
        ("|a\n", "Gviwy", "|a\n"),
        ("|a\n", "Gviw<Esc>x", "|\n"),
        ("|", "viwd", "|"),
        ("|", "diw", "|"),
        ("|\n", "Gviwd", "|"),
        ("|\n", "viwd", "|"),
        ("|a b\n", "Gviwd", "a |b"),
    ])
    func wordOnTheEmptyLastLine(start: String, keys: String, expected: String) {
        #expect(VimEngineTests.marked(VimEngineTests.run(start, keys)) == expected)
    }

    /// dif's text where Doom's cursor column depends on the major mode (checked in emacs --batch:
    /// python-mode and js-mode leave the cursor at the line's start there).
    @Test func defunTextInOtherModes() {
        #expect(VimEngineTests.run("class A:\n    def f(self):\n        |a\n    def g(self):\n        b", "dif").string == "class A:\n    def g(self):\n        b")
        #expect(VimEngineTests.run("function f() {\n  |a;\n}\nfunction g() {}", "dif").string == "function g() {}")
    }

    /// = asks the window for the lines to re-indent; the window runs Re-indent's formatter.
    @Test(arguments: [
        ("(a)\n|(b\nc)\n\n(d)", "=ip", 0...2), ("(a)\n|(b\nc)", "==", 1...1), ("(a)\n|(b\nc)", "=j", 1...2),
        ("(a)\n|(b\nc)", "Vj=", 1...2), ("|(a)\n(b)\n(c)", "2==", 0...1), ("(a\n |b)", "=i(", 0...1),
    ])
    func reindentAsksForTheLines(start: String, keys: String, lines: ClosedRange<Int>) {
        let engine = VimEngineTests.run(start, keys)
        #expect(engine.reindentRequest == lines)
        #expect(engine.string == start.replacingOccurrences(of: "|", with: ""))
    }

    @Test func reindentTakesOnlyTheIndentationOfItsLines() {
        // The formatter also tidies spaces inside a line ("(+  a x)"); = keeps the line's text.
        let original = "(defn f [x]\n(let [a 1]\n(+  a x)))\n(g\n   y)"
        let formatted = "(defn f [x]\n  (let [a 1]\n    (+ a x)))\n(g\n y)"
        var engine = VimEngine(original)
        engine.applyReindent(formatted, lines: 1...2, original: original)
        #expect(engine.string == "(defn f [x]\n  (let [a 1]\n    (+  a x)))\n(g\n   y)")
        #expect(VimEngineTests.marked(engine).hasPrefix("(defn f [x]\n  |(let"))
        _ = engine.handle(VimEngineTests.keys("u"))
        #expect(engine.string == original)
    }

    @Test func reindentLeavesTextThatChanged() {
        var engine = VimEngine("a\nb")
        engine.applyReindent("  a\n  b", lines: 0...1, original: "a\nX")
        #expect(engine.string == "a\nb")
        #expect(engine.message == "=: the text changed while formatting; nothing was re-indented")
        // A line the formatter's result has no match for keeps its indentation.
        engine.applyReindent("  a b", lines: 0...1, original: "a\nb")
        #expect(engine.string == "a\nb")
    }

    /// cljfmt drops runs of blank lines (2026-11-21, review: = refused such text); lines are
    /// matched by their text, so the rest still take their indentation.
    @Test func reindentMatchesLinesWhenTheFormatterDropsBlankLines() {
        let original = "(defn f [x]\nx)\n\n\n(g\ny)\n"
        let formatted = "(defn f [x]\n  x)\n\n(g\n y)\n"
        var engine = VimEngine(original)
        engine.applyReindent(formatted, lines: 0...6, original: original)
        #expect(engine.string == "(defn f [x]\n  x)\n\n\n(g\n y)\n")
    }

    /// Slurp, barf and raise on broken or tricky Lisp (2026-11-21 review: a stray ")" made slurp
    /// loop forever; brackets in comments and \" characters misled the scanners). Expected
    /// results are smartparens' in emacs --batch, clojure-mode.
    @Test(.timeLimit(.minutes(1)), arguments: [
        ("(fo|o) bar)", "<C-l>", "(fo|o bar))"), ("a) (b| c)", "<C-h>", "a) (b| c)"), ("(a ; (\n b| c)", "<D-R>", "|c"),
        ("(a ; say \"hi\n (b| c) d)", "<C-l>", "(a ; say \"hi\n (b| c d))"), ("(str \\\" (b| c) d)", "<C-l>", "(str \\\" (b| c d))"),
        ("(a \\( (b| c) d)", "<C-l>", "(a \\( (b| c d))"),
    ])
    func structuralEditsOnTrickyText(start: String, keys: String, expected: String) {
        #expect(VimEngineTests.marked(VimEngineTests.run(start, keys)) == expected)
    }

    /// ⌃H and ⌃J replay in a macro (they were stored as Backspace and a line break).
    @Test func slurpAndBarfKeysReplayInMacros() {
        #expect(VimEngineTests.run("(a (b| c) d e)", "qa<C-h>qu@a").string == "((a b c) d e)")
        #expect(VimEngineTests.run("(a (b| c d e) f)", "qa<C-j>qu@a").string == "(a (b c d) e f)")
    }
}
