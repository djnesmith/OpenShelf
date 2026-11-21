import Testing
@testable import OpenShelf

/// Unknown and unbuilt commands never let the keys after them run on their own
/// (2026-11-20: `=ip` and `ma` fell into insert mode, `cgnX` deleted a character).
struct VimUnknownCommandTests {
    static let start = "(defn f [a]\n  (let [x| 1]\n    x))"

    @Test(arguments: [
        ("g'a", "g'a: not built"), ("g`a", "g`a: not built"), ("''", "'': not built"), ("`.", "`.: not built"),
        ("g?iw", "g?iw: not built"),
        ("zz", "zz: not built"), ("zt", "zt: not built"), ("[x", "[x: not built"),
        ("gx", nil), ("!ip", "!ip: not built"),
    ] as [(String, String?)])
    func unbuiltCommandsDoNothingAndSayWhy(keys: String, hint: String?) {
        let engine = VimEngineTests.run(Self.start, keys)
        #expect(engine.string == VimEngineTests.engine(Self.start).string, "\(keys)")
        #expect(engine.mode == .normal, "\(keys)")
        if let hint { #expect(engine.failureHint == hint, "\(keys)") }
    }

    /// A change that can't run drops the typing meant for insert mode, until Esc.
    @Test func aFailedChangeIgnoresTypingUntilEscape() {
        let engine = VimEngineTests.run("a|bc", "cgnhello<Esc>x")
        #expect(VimEngineTests.marked(engine) == "a|c")
        let dropped = VimEngineTests.run("a|bc", "cgnhello")
        #expect(dropped.ignoresTyping)
        #expect(dropped.failureHint == "typing ignored until Esc")
        #expect(dropped.string == "abc")
    }

    /// Keys that start a longer command in vim (an operator, a mark, a register, a find,
    /// a g or z command). Alone, each must wait for the next key, never fail and drop it.
    static let vimPrefixes = Array("dcy<>=!gzm'`[]\"q@fFtTrZ")

    @Test func aPrefixKeyWaits() {
        for key in Self.vimPrefixes {
            var engine = VimEngineTests.engine(Self.start)
            _ = engine.handle(.char(key))
            #expect(engine.failureHint == nil, "\(key)")
            #expect(engine.mode == .normal, "\(key)")
        }
    }

    /// Every prefix with every second key: when the pair fails, nothing ran: the text,
    /// the mode and (for a change) the typing that follows are all held.
    @Test func aFailedPairChangesNothing() {
        let seconds = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ=!?@'`[]{}()<>;,.*#$%^&~_-+|\\/\"0123")
        var leaks: [String] = []
        for first in Self.vimPrefixes {
            for second in seconds {
                var engine = VimEngineTests.engine(Self.start)
                let before = engine.string
                _ = engine.handle(.char(first))
                _ = engine.handle(.char(second))
                guard engine.failureHint != nil else { continue }
                if engine.string != before || engine.mode != .normal { leaks.append("\(first)\(second)") }
                // A change that failed holds the next keys.
                _ = engine.handle(VimEngineTests.keys("ihello"))
                if first == "c", engine.string != before { leaks.append("\(first)\(second)ihello") }
            }
        }
        #expect(leaks.isEmpty, "\(leaks.prefix(20))")
    }
}
