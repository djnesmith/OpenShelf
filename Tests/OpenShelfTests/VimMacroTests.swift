import Testing
@testable import OpenShelf

/// q{a-z} records, q stops, @{a-z} plays, @@ plays the last one again.
/// The first two cases were checked against vim, fed as typed keys.
struct VimMacroTests {
    static func run(_ start: String, _ keys: String) -> VimEngine {
        VimEngineTests.run(start, keys)
    }

    @Test func recordAndPlay() {
        #expect(VimEngineTests.marked(Self.run("|a\nb\nc", "qaA!<Esc>jq@a@@")) == "a!\nb!\nc|!")
        #expect(VimEngineTests.marked(Self.run("|a\nb\nc\nd\ne", "qaA!<Esc>jq3@a")) == "a!\nb!\nc!\nd!\n|e")
    }

    @Test func recordingShowsAndStops() {
        var engine = VimEngineTests.engine("|a")
        _ = engine.handle(VimEngineTests.keys("qb"))
        #expect(engine.recording == "b")
        _ = engine.handle(VimEngineTests.keys("xq"))
        #expect(engine.recording == nil)
        #expect(engine.registers["b"]?.text == "x")
    }

    /// Macros live in the named registers: a recorded one pastes, a yanked one plays.
    @Test func macrosShareTheNamedRegisters() {
        #expect(Self.run("|a\nb", "qaA!<Esc>q").registers["a"]?.text == "A!\u{1b}")
        #expect(VimEngineTests.marked(Self.run("|dw one two", "\"ayiw@a")) == "|one two")
        // Playing a macro while recording records "@a", not its keys.
        #expect(Self.run("|abc", "qaxqqb@aq").registers["b"]?.text == "@a")
        // qA appends to a.
        #expect(Self.run("|ab", "qaxqqAxq").registers["a"]?.text == "xx")
    }

    /// The text view types insert mode itself; the recording still gets it.
    @Test func insertTypedByTheViewIsRecorded() {
        var engine = VimEngineTests.engine("|a\nb")
        _ = engine.handle(VimEngineTests.keys("qaA"))
        engine.syncInsert(text: "a!\nb", cursor: 2)
        _ = engine.handle(VimEngineTests.keys("<Esc>jq"))
        #expect(engine.registers["a"]?.text == "A!\u{1b}j")
        _ = engine.handle(VimEngineTests.keys("k@a"))
        #expect(engine.string == "a!!\nb")
    }

    /// A macro stops at the first command that fails.
    @Test func aFailingCommandStopsTheMacro() {
        #expect(Self.run("|a,b,c,d", "qaf,xq5@a").string == "abcd")
        // A recursive macro stops when j can't move.
        #expect(VimEngineTests.marked(Self.run("|a\nb\nc\nd", "qaqqajdd@aq@a")) == "a\n|c")
    }

    /// A motion that can't move is an error, so these stop where vim's do.
    @Test func motionsThatCantMoveStopTheMacro() {
        // Each is recursive (qaq clears a first), so only an error ends it.
        let append = Self.run("|abc\nnext\nz", "qaqqaa-<Esc>l@aq@a")
        #expect(append.string == "a-b-c-\nnext\nz")
        #expect(append.message == nil)
        let join = Self.run("|a\nb\nc\nd", "qaqqaJ@aq@a")
        #expect(join.string == "a b c d")
        #expect(join.message == nil)
        #expect(Self.run("|abcd", "$qaqqaXh@aq@a").string == "bd")
    }

    /// q inside a playing macro is ignored, as in vim; it used to crash.
    @Test func qInsideAMacroIsIgnored() {
        var engine = VimEngineTests.engine("|qbxq abc")
        _ = engine.handle(VimEngineTests.keys("\"ayW@a"))
        #expect(engine.recording == nil)
        #expect(engine.registers["b"] == nil)
    }

    @Test func qInVisualModeStopsRecording() {
        let engine = Self.run("|abc", "qaxvq")
        #expect(engine.recording == nil)
        #expect(engine.registers["a"]?.text == "xv")
    }

    /// One u takes back everything a macro did.
    @Test func undoTakesBackTheWholeMacro() {
        #expect(Self.run("|abcd", "qaxxqu@au").string == "bcd")
        #expect(Self.run("|abcdefgh", "qaxxqu3@au").string == "bcdefgh")
    }

    /// A macro can't close the window: it stops instead.
    @Test func aMacroCantCloseTheWindow() {
        var engine = VimEngineTests.engine("|xZZx abc")
        let effect = engine.handle(VimEngineTests.keys("\"ayiw0dW@a"))
        #expect(effect == nil)
        #expect(engine.message == "Macro stopped: it would have closed the window")
    }

    @Test func runawayMacrosAreStopped() {
        var deep = VimEngineTests.engine("|a")
        _ = deep.handle(VimEngineTests.keys("qaq" + "qa0@aq@a"))
        #expect(deep.message == "Macro stopped after \(VimEngine.macroKeyLimit) keys")
        var long = VimEngineTests.engine("|a")
        _ = long.handle(VimEngineTests.keys("qa0q\(VimEngine.macroKeyLimit + 1)@a"))
        #expect(long.message == "Macro stopped after \(VimEngine.macroKeyLimit) keys")
    }

    @Test func keysSurviveTheRoundTripThroughARegister() {
        let keys: [VimKey] = [.char("x"), .escape, .enter, .backspace, .ctrl("r"), .ctrl("["), .left, .right, .up, .down, .char("\n")]
        let back = keys.map { VimEngine.key(for: VimEngine.character(for: $0)) }
        #expect(back == [.char("x"), .escape, .enter, .backspace, .ctrl("r"), .escape, .left, .right, .up, .down, .char("\n")])
    }
}
