import Foundation
import Testing
@testable import OpenShelf

struct LineTransformsTests {
    typealias L = LineTransforms

    @Test func lineTextKeepsEndingsAndTheLastNewline() {
        #expect(LineText("").lines == [])
        #expect(LineText("a").lines == ["a"])
        let shape = LineText("a\nb\n")
        #expect(shape.lines == ["a", "b"] && shape.separator == "\n" && shape.endsWithNewline)
        #expect(LineText("a\r\nb").separator == "\r\n")
        #expect(LineText("\n").lines == [""])
        for text in ["", "a", "a\n", "a\nb", "a\r\nb\r\n", "\n", "a\n\nb\n\n"] {
            #expect(LineText(text).text == text, "\(text.debugDescription)")
        }
        #expect(LineText("b\ra\r").lines == ["b", "a"])
        #expect(L.sortAZ("b\ra") == "a\rb")
        #expect(L.sortAZ("b\u{2028}a") == "a\u{2028}b")
    }

    @Test func sortAZIgnoresCaseAndKeepsTies() {
        #expect(L.sortAZ("pear\nApple\nbanana\n") == "Apple\nbanana\npear\n")
        #expect(L.sortAZ("b\r\na\r\n") == "a\r\nb\r\n")
        #expect(L.sortAZ("b\nB\na\nb") == "a\nb\nB\nb")
        #expect(L.sortAZ("élan\nzebra\neagle") == "eagle\nélan\nzebra")
        #expect(L.sortAZ("a\nb\nc") == "a\nb\nc")
        #expect(L.sortAZ("") == "")
        #expect(L.sortAZ("one line") == "one line")
        #expect(L.sortAZ("b\n\na\n\n") == "a\nb\n\n\n")
    }

    @Test func sortNaturalPutsNumbersInOrder() {
        #expect(L.sortNatural("file 10\nfile 2\nFile 1") == "File 1\nfile 2\nfile 10")
        #expect(L.sortAZ("file 10\nfile 2") == "file 10\nfile 2")
    }

    @Test func sortByLengthIsShortestFirstAndStable() {
        #expect(L.sortByLength("ccc\na\nbb\nd\n") == "a\nd\nbb\nccc\n")
        #expect(L.sortByLength("👩‍👩‍👧\nab") == "👩‍👩‍👧\nab")
    }

    @Test func reverseAndShuffle() {
        #expect(L.reverse("1\n2\n3\n") == "3\n2\n1\n")
        #expect(L.reverse("only") == "only")
        let text = (1...20).map(String.init).joined(separator: "\n") + "\n"
        var generator = SeededGenerator(seed: 7)
        let shuffled = L.shuffle(text, using: &generator)
        #expect(shuffled != text)
        #expect(shuffled.hasSuffix("\n"))
        #expect(LineText(shuffled).lines.sorted() == LineText(text).lines.sorted())
        for seed in 0..<20 {
            var twoLines = SeededGenerator(seed: UInt64(seed))
            #expect(L.shuffle("a\nb", using: &twoLines) == "b\na")
        }
        #expect(L.shuffle("same\nsame") == "same\nsame")
    }

    @Test func removeDuplicatesKeepsTheFirst() {
        #expect(L.removeDuplicates("a\nb\na\nc\nb\n") == "a\nb\nc\n")
        #expect(L.removeDuplicates("a\nA\na ") == "a\nA\na ")
        #expect(L.removeDuplicates("x\r\nx\r\n") == "x\r\n")
    }

    @Test func removeBlankLinesTakesWhitespaceOnlyLines() {
        #expect(L.removeBlankLines("a\n\n  \n\tb\n\t\nc\n") == "a\n\tb\nc\n")
        #expect(L.removeBlankLines("\n\n") == "")
    }

    @Test func numberSkipsBlankLines() {
        #expect(L.number("a\nb\n\nc\n") == "1. a\n2. b\n\n3. c\n")
        #expect(L.number("3. a\n  7. b\n10. c") == "1. a\n  2. b\n3. c")
        #expect(L.number("") == "")
    }

    @Test func markdownListKeepsIndentAndExistingItems() {
        #expect(L.markdownList("milk\n  eggs\n\n- bread\n") == "- milk\n  - eggs\n\n- bread\n")
    }

    @Test func joinAndSplitAreOpposites() {
        #expect(L.join("a\n b \n\nc\n", with: ", ") == "a, b, c\n")
        #expect(L.join("b\na", with: ", ") == "b, a")
        #expect(L.join("a\r\nb", with: " ") == "a b")
        #expect(L.split("a, b,,c", at: ",") == "a\nb\nc")
        #expect(L.split("a,b\nc\n", at: ",") == "a\nb\nc\n")
        #expect(L.split(L.join("x\ny\nz", with: ", "), at: ",") == "x\ny\nz")
        #expect(L.splitAtSpaces("one  two\tthree") == "one\ntwo\nthree")
        #expect(L.split("a,b\n\nc", at: ",") == "a\nb\n\nc")
        #expect(L.splitAtSpaces("a b\n\nc") == "a\nb\n\nc")
    }

    @Test func quoteAndUnquoteRoundTrip() {
        let text = "  plain\nsay \"hi\"\n\nback\\slash\n"
        let quoted = L.quote(text)
        #expect(quoted == "  \"plain\"\n\"say \\\"hi\\\"\"\n\n\"back\\\\slash\"\n")
        #expect(L.unquote(quoted) == text)
    }

    @Test func unquoteHandlesSingleQuotesCommasAndOtherEscapes() {
        #expect(L.unquote("'a',\n\"b\",\n\"c\"") == "a,\nb,\nc")
        #expect(L.unquote(#""line\n""#) == #"line\n"#)
        #expect(L.unquote("\"mismatched'\nx") == "\"mismatched'\nx")
        #expect(L.unquote("\"") == "\"")
        #expect(L.unquote("\"foo\" and \"bar\"") == "\"foo\" and \"bar\"")
        #expect(L.unquote("'it's'\n'a' or 'b'") == "it's\n'a' or 'b'")
    }

    @Test func addCommasSkipsTheLastLine() {
        #expect(L.addCommas("a\nb  \n\nc\n") == "a,\nb,\n\nc\n")
        #expect(L.addCommas("a,\nb") == "a,\nb")
        #expect(L.addCommas("only") == "only")
        #expect(L.addCommas("") == "")
    }

    /// The edges the brief named, on every Lines and Case tool: nothing in,
    /// nothing out; one line stays one line; a final newline and CRLF stay.
    @Test(arguments: TextGroup.allCases.flatMap(\.wedges).compactMap { command -> TextTool? in
        guard case .tool(let tool) = command, ![.dedent, .indent, .outdent, .tabsSpaces, .trimLines, .straightenQuotes].contains(tool) else { return nil }
        return tool
    })
    func everyLineAndCaseToolKeepsTheShape(tool: TextTool) throws {
        #expect(tool.apply(to: "") == "")
        let one = try #require(tool.apply(to: "x y"))
        #expect(!one.contains("\n") || tool == .splitAtSpaces || tool == .markdownTable)
        #expect(try #require(tool.apply(to: "x y\n")).hasSuffix("\n"))
        #expect(!(try #require(tool.apply(to: "x y")).hasSuffix("\n")))
        let crlf = try #require(tool.apply(to: "b a\r\nA b\r\n"))
        #expect(crlf.hasSuffix("\r\n"), "\(crlf.debugDescription)")
        #expect(!crlf.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "\(crlf.debugDescription)")
    }

    @Test func csvBecomesAMarkdownTable() {
        #expect(L.markdownTable("name,age\nAnn,30\nBo,4\n") == "| name | age |\n| --- | --- |\n| Ann | 30 |\n| Bo | 4 |\n")
    }

    @Test func tableHandlesTabsQuotesPipesAndShortRows() {
        #expect(L.markdownTable("a\tb\n1\t2") == "| a | b |\n| --- | --- |\n| 1 | 2 |")
        #expect(L.markdownTable("h1,h2,h3\n\"x, y\",\"say \"\"hi\"\"\"\na|b") ==
            "| h1 | h2 | h3 |\n| --- | --- | --- |\n| x, y | say \"hi\" |  |\n| a\\|b |  |  |")
        #expect(L.markdownTable("a,b\r\n\"two\nlines\",c\r\n") == "| a | b |\r\n| --- | --- |\r\n| two<br>lines | c |\r\n")
        #expect(L.markdownTable("solo") == "| solo |\n| --- |")
        #expect(L.markdownTable("a,b\n1,2,3") == "| a | b |  |\n| --- | --- | --- |\n| 1 | 2 | 3 |")
        #expect(L.markdownTable("") == "")
        #expect(L.markdownTable("q,x\n\"Hello\" she said,1") == "| q | x |\n| --- | --- |\n| Hello she said | 1 |")
        #expect(L.markdownTable("a,b\n\"x\"  ,1") == "| a | b |\n| --- | --- |\n| x | 1 |")
        #expect(L.markdownTable("a,b\n\"open,1\nc,2") == "| a | b |\n| --- | --- |\n| \"open | 1 |\n| c | 2 |")
    }

    @Test func parseSkipsBlankLinesAndKeepsQuotedSpaces() {
        #expect(L.parseDelimited("a, b\n\n c ,\" d \"", delimiter: ",") == [["a", "b"], ["c", " d "]])
    }
}

/// A repeatable generator for the shuffle test (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
