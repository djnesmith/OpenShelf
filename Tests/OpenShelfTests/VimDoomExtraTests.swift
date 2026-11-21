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
}
