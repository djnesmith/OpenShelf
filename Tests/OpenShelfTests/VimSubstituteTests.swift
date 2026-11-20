import Foundation
import Testing
@testable import OpenShelf

/// `:s` (ROADMAP C12). Expected results are vim 9.2's (vim --clean).
struct VimSubstituteTests {
    @Test(arguments: [
        ("a|a a\nb a\na a", ":s/a/X/<CR>", "|Xa a\nb a\na a"),
        ("a|a a\nb a\na a", ":s/a/X/g<CR>", "|XX X\nb a\na a"),
        ("a|a a\nb a\na a", ":%s/a/X/g<CR>", "XX X\nb X\n|X X"),
        ("a|a a\nb a\na a", ":%s/a/X/<CR>", "Xa a\nb X\n|X a"),
        ("one two\nthree\n|four", ":1,2s/o/0/g<CR>", "|0ne tw0\nthree\nfour"),
        ("foo(bar)\n|x", ":%s/\\(\\w\\+\\)(\\(\\w\\+\\))/\\2-\\1/<CR>", "|bar-foo\nx"),
        ("a.b.c|", ":s/\\./,/g<CR>", "|a,b,c"),
        ("cat dog|", ":s/\\<dog\\>/[&]/<CR>", "|cat [dog]"),
        ("a,b|", ":s/,/\\r/<CR>", "a\n|b"),
        ("x|yz", ":s/q/Z/<CR>", "x|yz"),
        ("a1 b22 c333|", ":s/\\d\\{2,}/N/g<CR>", "|a1 bN cN"),
        ("Hello hello|", ":s/hello/X/gi<CR>", "|X X"),
        ("aaa\n|aaa", ":s/a/b/<CR>:%s//c/g<CR>", "ccc\n|bcc"),
        ("one|\ntwo", ":s/o/0/<CR>j&", "0ne\n|tw0"),
        ("ab|c", ":s/b/$1/<CR>", "|a$1c"),
        ("tab|", ":s/a/\\t/<CR>", "|t\tb"),
        ("x|", ":s/x/a\\\\b/<CR>", "|a\\b"),
        ("a+b|", ":s/+/plus/<CR>", "|aplusb"),
        ("a|b", ":s/a\\|b/X/g<CR>", "|XX"),
        ("line one\nline two\nline three|", ":%s/line/L/<CR>", "L one\nL two\n|L three"),
        ("a\n|b\nc\nd", "Vj:s/./X/<CR>", "a\nX\n|X\nd"),
        // An empty pattern is the last one searched for with /.
        ("|abc\nabc", "/b<CR>:s//X/<CR>", "|aXc\nabc"),
        // & repeats without the g flag.
        ("|aa\naa", ":s/a/X/g<CR>j&", "XX\n|Xa"),
    ])
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(VimCountTests.run(start, keys) == expected)
    }

    @Test func notFoundSaysSo() {
        var engine = VimEngineTests.engine("a|bc")
        _ = engine.handle(VimEngineTests.keys(":s/q/x/<CR>"))
        #expect(engine.message == "E486: Pattern not found: q")
        #expect(engine.string == "abc")
    }

    @Test func oneOrTwoLinesSayNothing() {
        var engine = VimEngineTests.engine("|a\na")
        _ = engine.handle(VimEngineTests.keys(":%s/a/b/<CR>"))
        #expect(engine.message == nil)
        #expect(engine.string == "b\nb")
    }

    @Test func manyLinesSayHowMany() {
        var engine = VimEngineTests.engine("|a\na\na")
        _ = engine.handle(VimEngineTests.keys(":%s/a/b/<CR>"))
        #expect(engine.message == "3 substitutions on 3 lines")
        _ = engine.handle(VimEngineTests.keys("u"))
        #expect(engine.string == "a\na\na")
    }

    /// In visual mode ":" starts with '<,'> and the substitute keeps to those lines.
    @Test func visualRange() {
        var engine = VimEngineTests.engine("|a\na\na\na")
        _ = engine.handle(VimEngineTests.keys("jVj:"))
        #expect(engine.commandLine == ":'<,'>")
        _ = engine.handle(VimEngineTests.keys("s/a/b/<CR>"))
        #expect(engine.string == "a\nb\nb\na")
    }

    @Test func parsesRangesAndFlags() {
        #expect(VimSubstitute.parse("%s/a/b/gi") == .init(range: .all, pattern: "a", replacement: "b", global: true, ignoreCase: true))
        #expect(VimSubstitute.parse("2,$s#x#y#") == .init(range: .lines(.number(2), .last), pattern: "x", replacement: "y", global: false, ignoreCase: nil))
        #expect(VimSubstitute.parse(".s/a\\/b/c/I")?.pattern == "a/b")
        #expect(VimSubstitute.parse(".s/a\\/b/c/I")?.ignoreCase == false)
        #expect(VimSubstitute.parse("s/a/b/q") == nil)
        #expect(VimSubstitute.parse("set wrap") == nil)
        #expect(VimSubstitute.parse("sort") == nil)
    }

    @Test func translatesVimPatterns() {
        #expect(VimSubstitute.icuPattern("\\(a\\|b\\)\\+(c)").pattern == "(a|b)+\\(c\\)")
        #expect(VimSubstitute.icuPattern("x\\{2,3}").pattern == "x{2,3}")
        #expect(VimSubstitute.icuPattern("\\<w\\>").pattern == "\\bw\\b")
        #expect(VimSubstitute.icuPattern("abc\\c").caseOverride == true)
        #expect(VimSubstitute.template("[&] \\1 $ \\& \\r") == "[$0] $1 \\$ & \n")
    }
}
