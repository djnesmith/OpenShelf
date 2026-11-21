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
}
