import Testing
@testable import OpenShelf

/// Each case is text with the cursor marked by "|", keys in vim notation
/// (<Esc>, <CR>, <BS>, <C-r>), and the text and cursor afterwards. The
/// expected results are what vim does with its defaults.
struct VimEngineTests {
    static func keys(_ notation: String) -> [VimKey] {
        var keys: [VimKey] = []
        var rest = Substring(notation)
        while let first = rest.first {
            if first == "<", let close = rest.firstIndex(of: ">") {
                let name = rest[rest.index(after: rest.startIndex)..<close]
                switch name {
                case "Esc": keys.append(.escape)
                case "CR": keys.append(.enter)
                case "BS": keys.append(.backspace)
                case "Left": keys.append(.left)
                case "Right": keys.append(.right)
                case "Up": keys.append(.up)
                case "Down": keys.append(.down)
                default:
                    if name.hasPrefix("C-"), let c = name.last { keys.append(.ctrl(c)) } else if name.hasPrefix("A-"), let c = name.last { keys.append(.alt(c)) } else { keys.append(contentsOf: VimKey.keys(String(rest[...close]))) }
                }
                rest = rest[rest.index(after: close)...]
            } else {
                keys.append(.char(first))
                rest = rest.dropFirst()
            }
        }
        return keys
    }

    /// An engine on `marked`, with the cursor where "|" is.
    static func engine(_ marked: String) -> VimEngine {
        let cursor = marked.distance(from: marked.startIndex, to: marked.firstIndex(of: "|")!)
        var engine = VimEngine(marked.replacingOccurrences(of: "|", with: ""))
        // Move there with motions, so the test also starts from a real state.
        _ = engine.handle(keys("gg0"))
        for _ in 0..<cursor { _ = engine.handle(.char("l")) }
        let lines = marked.prefix(cursor).filter { $0 == "\n" }.count
        if lines > 0 {
            _ = engine.handle(keys("gg0"))
            _ = engine.handle(keys(String(lines) + "j0"))
            let column = marked.prefix(cursor).split(separator: "\n", omittingEmptySubsequences: false).last!.count
            for _ in 0..<column { _ = engine.handle(.char("l")) }
        }
        return engine
    }

    static func marked(_ engine: VimEngine) -> String {
        var text = engine.text
        text.insert("|", at: engine.cursor)
        return String(text)
    }

    static func run(_ start: String, _ notation: String) -> VimEngine {
        var engine = engine(start)
        _ = engine.handle(keys(notation))
        return engine
    }

    @Test(arguments: [
        // h j k l, counts, and the column j and k remember.
        ("ab|cd", "h", "a|bcd"),
        ("ab|cd", "9l", "abc|d"),
        ("ab|cd", "9h", "|abcd"),
        ("abc|d\nx\nabcd", "jj", "abcd\nx\nabc|d"),
        ("abc|d\nx\nabcd", "j", "abcd\n|x\nabcd"),
        ("a|b\ncd", "<Down>", "ab\nc|d"),
        // Words.
        ("|foo bar.baz qux", "w", "foo |bar.baz qux"),
        ("|foo bar.baz qux", "2w", "foo bar|.baz qux"),
        ("|foo bar.baz qux", "2W", "foo bar.baz |qux"),
        ("foo bar.baz |qux", "b", "foo bar.|baz qux"),
        ("foo bar.baz |qux", "B", "foo |bar.baz qux"),
        ("|foo bar", "e", "fo|o bar"),
        // A count goes as far as there are words.
        ("a\nb\n|c\nd", "2e", "a\nb\nc\n|d"),
        ("fo|o bar", "e", "foo ba|r"),
        ("|a\n\nb", "w", "a\n|\nb"),
        ("a\n\n|b", "b", "a\n|\nb"),
        // Line positions.
        ("  ab|c", "0", "|  abc"),
        ("  ab|c", "^", "  |abc"),
        ("|abc\ndef", "$", "ab|c\ndef"),
        ("|abc\ndef", "2$", "abc\nde|f"),
        ("a\n  b\n|c", "gg", "|a\n  b\nc"),
        ("|a\n  b\nc", "G", "a\n  b\n|c"),
        ("|a\n  b\nc", "2G", "a\n  |b\nc"),
        ("|a\n  b\nc", ":2<CR>", "a\n  |b\nc"),
        // Find.
        ("|a,b,c", "f,", "a|,b,c"),
        ("|a,b,c", "2f,", "a,b|,c"),
        ("|a,b,c", "f,;", "a,b|,c"),
        ("|a,b,c", "t,", "|a,b,c"),
        ("|aa,b,c", "t,", "a|a,b,c"),
        ("|aa,b,c", "t,;", "aa,|b,c"),
        ("a,b,|c", "F,", "a,b|,c"),
        ("a,b,|c", "T,", "a,b,|c"),
        ("|a,b,c", "2f,,", "a|,b,c"),
        ("|a,b,c", "fz", "|a,b,c"),
        // Brackets and paragraphs.
        ("|f(a(b)c)", "%", "f(a(b)c|)"),
        ("f(a(b)c|)", "%", "f|(a(b)c)"),
        ("|a\nb\n\nc", "}", "a\nb\n|\nc"),
        ("a\nb\n\n|c", "{", "a\nb\n|\nc"),
        // Search, smartcase, wrapping, n and N.
        ("|one Two one two", "/two<CR>", "one |Two one two"),
        ("|one Two one two", "/two<CR>n", "one Two one |two"),
        ("|one Two one two", "/Two<CR>n", "one |Two one two"),
        ("one Two one |two", "/one<CR>", "|one Two one two"),
        ("|one Two one two", "/one<CR>N", "|one Two one two"),
        ("|foo foobar foo", "*", "foo foobar |foo"),
        ("foo foobar |foo", "#", "|foo foobar foo"),
    ])
    func motions(start: String, keys: String, expected: String) {
        #expect(Self.marked(Self.run(start, keys)) == expected)
    }

    @Test(arguments: [
        // Delete.
        ("|foo bar baz", "dw", "|bar baz"),
        ("|foo bar baz", "2dw", "|baz"),
        ("|foo bar baz", "d2w", "|baz"),
        ("foo |bar\nbaz", "dw", "foo| \nbaz"),
        ("|foo bar", "de", "| bar"),
        ("|foo bar", "d$", "|"),
        ("fo|o bar", "D", "f|o"),
        ("|abc", "x", "|bc"),
        ("ab|c", "x", "a|b"),
        ("|abc", "2x", "|c"),
        ("ab|c", "X", "a|c"),
        ("|a,b,c", "dt,", "|,b,c"),
        ("|a,b,c", "df,", "|b,c"),
        ("|f(a(b)c) d", "d%", "| d"),
        ("one\n|two\nthree", "dd", "one\n|three"),
        ("one\ntwo\n|three", "dd", "one\n|two"),
        ("|one\ntwo\nthree", "2dd", "|three"),
        ("|one\ntwo\nthree", "dj", "|three"),
        ("one\ntwo\n|three", "dk", "|one"),
        ("one\n|two\nthree", "dG", "|one"),
        ("one\n|two\nthree", "dgg", "|three"),
        ("  |only", "dd", "|"),
        // Edge rules found by comparing random keys with vim.
        ("|a\nb\nc\nd", "d2w", "|c\nd"),
        ("|ab cd\nef", "d2w", "|\nef"),
        ("x |aa\nbb\ncc", "d2w", "x| \ncc"),
        ("a\n|b\nc\nd", "5dd", "|a"),
        ("a\nb\nc\n|d", "2dd", "a\nb\nc\n|d"),
        ("a\nb\n|c", "dj", "a\nb\n|c"),
        ("a\nb\n|c", "d5k", "|"),
        ("|a b\n\nc", "jd$", "a b\n|\nc"),
        ("|a\n  b", "J", "a| b"),
        ("a| \n  b", "J", "a |b"),
        ("foo|\n\nlast", "jdb", "|\nlast"),
        ("word\n\n|\nword2 w3\n", "dG2p", "word\n\n|\nword2 w3\n\n\nword2 w3\n"),
        ("o|ne two", "ddC!<Esc>p", "!\n|one two"),
        // Undo leaves the cursor where the change began.
        ("foo |bar\nbaz", "ddu", "|foo bar\nbaz"),
        // Text that spans lines pastes with the cursor at its start.
        ("|ab\ncd", "vjy$p", "ab|ab\nc\ncd"),
        ("|a\nb", "Ox<Esc>", "|x\na\nb"),

        ("|foo bar", "cwxy<Esc>", "x|y bar"),
        ("fo|o bar", "cwX<Esc>", "fo|X bar"),
        ("|foo bar baz", "c2wX<Esc>", "|X baz"),
        ("|foo bar", "c$X<Esc>", "|X"),
        ("fo|o bar", "CX<Esc>", "fo|X"),
        ("|abc", "sX<Esc>", "|Xbc"),
        // cc, S, o and O keep the indentation, as with vim's autoindent and in evil.
        ("  fo|o\nbar", "ccX<Esc>", "  |X\nbar"),
        ("  fo|o\nbar", "SX<Esc>", "  |X\nbar"),
        // Yank and put.
        ("|foo bar", "ywP", "foo| foo bar"),
        ("|foo bar", "ywp", "ffoo| oo bar"),
        ("|one\ntwo", "yyp", "one\n|one\ntwo"),
        ("one\n|two", "yyp", "one\ntwo\n|two"),
        ("one\n|two", "yyP", "one\n|two\ntwo"),
        ("|one\ntwo", "yy2p", "one\n|one\none\ntwo"),
        ("|one\ntwo", "ddp", "two\n|one"),
        ("|ab", "xp", "b|a"),
        ("fo|o bar", "y$P", "foo ba|ro bar"),
        // Y is y$, as in Neovim (vim's own Y is yy).
        ("fo|o bar", "Yp", "fooo ba|r bar"),
        // Indent and case.
        ("|a\nb", ">>", "    |a\nb"),
        ("|a\nb", "2>>", "    |a\n    b"),
        ("|a\nb", ">j", "    |a\n    b"),
        ("    |a", "<<", "|a"),
        ("|abc def", "gUw", "|ABC def"),
        ("|abc def", "gUU", "|ABC DEF"),
        ("|Abc", "g~~", "|aBC"),
        ("|abc", "~", "A|bc"),
        ("|abc", "5~", "AB|C"),
        // Replace, join, open lines.
        ("|abc", "rX", "|Xbc"),
        ("|abc", "2rX", "X|Xc"),
        ("|abc", "9rX", "|abc"),
        ("|a\n  b\nc", "J", "a| b\nc"),
        ("|a\n  b\nc", "3J", "a b| c"),
        ("|a\n\nc", "J", "|a\nc"),
        ("|a\n)", "J", "a|)"),
        ("  |a\nb", "ox<Esc>", "  a\n  |x\nb"),
        ("  |a\nb", "Ox<Esc>", "  |x\n  a\nb"),
        // Insert positions.
        ("a|bc", "iX<Esc>", "a|Xbc"),
        ("a|bc", "aX<Esc>", "ab|Xc"),
        ("a|bc", "AX<Esc>", "abc|X"),
        ("  a|bc", "IX<Esc>", "  |Xabc"),
        ("|abc", "iX<BS>Y<Esc>", "|Yabc"),
        ("|ab", "i1<CR>2<Esc>", "1\n|2ab"),
    ])
    func operators(start: String, keys: String, expected: String) {
        #expect(Self.marked(Self.run(start, keys)) == expected)
    }

    @Test(arguments: [
        ("|abcdef", "vld", "|cdef"),
        ("|abcdef", "vey", "|abcdef"),
        ("ab|cdef", "vhhd", "|def"),
        ("ab|cdef", "vlohd", "a|ef"),
        ("|one\ntwo\nthree", "Vjd", "|three"),
        ("|one\ntwo", "VU", "|ONE\ntwo"),
        ("|abc", "v~", "|Abc"),
        ("|a\nb", "Vj>", "    |a\n    b"),
        ("|a\nb\nc", "VjJ", "a| b\nc"),
        ("|abc", "vlcX<Esc>", "|Xc"),
        ("|abc", "vl<Esc>x", "a|c"),
        // In visual mode l reaches the line break, so d takes it.
        ("a\n|b\nc", "vlld", "a\n|c"),
        ("(|a b", "vey", "(|a b"),
    ])
    func visual(start: String, keys: String, expected: String) {
        #expect(Self.marked(Self.run(start, keys)) == expected)
    }

    @Test func undoAndRedo() {
        var engine = Self.engine("|one two three")
        _ = engine.handle(Self.keys("dwdw"))
        #expect(engine.string == "three")
        _ = engine.handle(Self.keys("u"))
        #expect(Self.marked(engine) == "|two three")
        _ = engine.handle(Self.keys("u"))
        #expect(engine.string == "one two three")
        #expect(!engine.isChanged)
        _ = engine.handle(Self.keys("u"))
        #expect(engine.message == "Already at oldest change")
        _ = engine.handle(Self.keys("<C-r><C-r>"))
        #expect(engine.string == "three")
        // A whole insert is one change; an insert that types nothing is none.
        _ = engine.handle(Self.keys("ix<Esc>ay<Esc>u"))
        #expect(engine.string == "xthree")
        _ = engine.handle(Self.keys("i<Esc>u"))
        #expect(engine.string == "three")
        // A new change drops the redo history.
        _ = engine.handle(Self.keys("x<C-r>"))
        #expect(engine.string == "hree")
    }

    @Test func modesAndSelection() {
        var engine = Self.engine("|ab\ncd")
        #expect(engine.mode == .normal)
        _ = engine.handle(Self.keys("vl"))
        #expect(engine.mode == .visual)
        #expect(engine.selection == 0..<2)
        _ = engine.handle(Self.keys("V"))
        #expect(engine.mode == .visualLine)
        #expect(engine.selection == 0..<3)
        _ = engine.handle(Self.keys("<Esc>"))
        #expect(engine.mode == .normal)
        #expect(engine.selection == nil)
        _ = engine.handle(Self.keys("i"))
        #expect(engine.mode == .insert)
        _ = engine.handle(.ctrl("["))
        #expect(engine.mode == .normal)
        // Esc in normal mode does nothing, and never closes the window.
        #expect(engine.handle(.escape) == nil)
        #expect(engine.mode == .normal)
    }

    @Test func finishAndCancel() {
        for finish in [":w<CR>", ":wq<CR>", ":x<CR>", "ZZ"] {
            var engine = Self.engine("|a")
            _ = engine.handle(Self.keys("x"))
            #expect(engine.handle(Self.keys(finish)) == .finish, "\(finish)")
        }
        for cancel in [":q!<CR>", "ZQ"] {
            var engine = Self.engine("|a")
            _ = engine.handle(Self.keys("x"))
            #expect(engine.handle(Self.keys(cancel)) == .cancel, "\(cancel)")
        }
        var unchanged = Self.engine("|a")
        #expect(unchanged.handle(Self.keys(":q<CR>")) == .cancel)
        var changed = Self.engine("|a")
        _ = changed.handle(Self.keys("x"))
        #expect(changed.handle(Self.keys(":q<CR>")) == nil)
        #expect(changed.message == "E37: No write since last change (add ! to override)")
        #expect(changed.handle(Self.keys(":nope<CR>")) == nil)
        #expect(changed.message == "E492: Not an editor command: nope")
        #expect(changed.mode == .normal)
        // Esc and backspace leave the command line without running it.
        _ = changed.handle(Self.keys(":q!<Esc>"))
        #expect(changed.mode == .normal)
        _ = changed.handle(Self.keys(":<BS>"))
        #expect(changed.mode == .normal)
        #expect(changed.handle(Self.keys(":<BS>ZQ")) == .cancel)
    }

    /// "." of a change that fails stops, so what it typed doesn't run as commands.
    @Test func repeatStopsWhenTheChangeFails() {
        var engine = Self.engine("say \"|a\"\nfoo bar")
        _ = engine.handle(Self.keys("ci\"xdd<Esc>j0."))
        #expect(engine.string == "say \"xdd\"\nfoo bar")
    }

    @Test func searchSaysWhenNothingMatches() {
        var engine = Self.engine("|abc")
        _ = engine.handle(Self.keys("n"))
        #expect(engine.message == "E35: No previous regular expression")
        _ = engine.handle(Self.keys("/zz<CR>"))
        #expect(engine.message == "E486: Pattern not found: zz")
        #expect(engine.cursor == 0)
    }

    /// The window types in insert mode itself, then hands the text over.
    @Test func insertTypedByTheViewIsKept() {
        var engine = Self.engine("|ab")
        _ = engine.handle(Self.keys("i"))
        engine.syncInsert(text: "xyab", cursor: 2)
        _ = engine.handle(.escape)
        #expect(Self.marked(engine) == "x|yab")
        _ = engine.handle(Self.keys("u"))
        #expect(engine.string == "ab")
    }

    /// Windows line breaks pasted while typing are lines too.
    @Test func crlfPastedInInsertModeBecomesLines() {
        var engine = Self.engine("|")
        _ = engine.handle(Self.keys("i"))
        engine.syncInsert(text: "a\r\nb\r\nc", cursor: 3)
        _ = engine.handle(Self.keys("<Esc>ggjdd"))
        #expect(engine.string == "a\nc")
    }

    /// A count of any length is capped rather than overflowing.
    @Test func hugeCountsAreCapped() {
        var engine = Self.engine("|abc def")
        _ = engine.handle(Self.keys("5000000000d5000000000w"))
        #expect(engine.string == "")
        var lines = Self.engine("|a\nb")
        _ = lines.handle(Self.keys("99999999999j"))
        #expect(lines.cursor == 2)
    }

    @Test func undoRemembersAThousandChanges() {
        var engine = Self.engine("|" + String(repeating: "x", count: VimEngine.undoLimit + 5))
        for _ in 0..<(VimEngine.undoLimit + 5) { _ = engine.handle(.char("x")) }
        #expect(engine.string == "")
        _ = engine.handle(Self.keys("\(VimEngine.undoLimit + 5)u"))
        #expect(engine.string == String(repeating: "x", count: VimEngine.undoLimit))
        #expect(engine.message == "Already at oldest change")
    }

    /// { and } read each line once, so a long text stays quick.
    @Test func paragraphMotionsStayFastOnLongText() {
        let text = (1...20_000).map { $0 % 50 == 0 ? "" : "line \($0)" }.joined(separator: "\n")
        var engine = VimEngine(text)
        let elapsed = ContinuousClock().measure { _ = engine.handle(Self.keys("}}G{")) }
        // About 0.1 s alone; the old quadratic version took 43 s. A wide bound,
        // so the rest of the suite running alongside can't fail it.
        #expect(elapsed < .seconds(3))
        #expect(engine.mode == .normal)
    }

    @Test func emptyTextTakesEveryKeyWithoutCrashing() {
        let notation = "hjklwbeWBE0^$ggG%{}nN*#xXsSDCYJoOpPu~vV<Esc>ddccyy>><<rXfa;,dwcwiw<Esc>"
        for key in Self.keys(notation) {
            var engine = VimEngine("")
            _ = engine.handle(key)
            _ = engine.handle(.escape)
            #expect(engine.cursor <= engine.text.count)
        }
        var engine = VimEngine("")
        _ = engine.handle(Self.keys(notation))
        #expect(engine.cursor <= engine.text.count)
    }

    /// A quote object that finds nothing says why (vim's quotes stay on one line, so a
    /// docstring over two lines has none), and so does a bracket object outside brackets.
    @Test func failedTextObjectsSayWhy() {
        #expect(Self.run("  \"Says hel|lo\n  more\"", "ci\"").failureHint == "ci\": no \"…\" on this line")
        #expect(Self.run("(= \\\" (fi|rst s))", "di\"").failureHint == "di\": no \"…\" on this line")
        #expect(Self.run("no br|ackets", "ci(").failureHint == "ci(: not inside ( )")
        #expect(Self.run("no br|ackets", "di{").failureHint == "di{: not inside { }")
        #expect(Self.run("\"o|k\"", "ci\"").failureHint == nil)
    }
}
