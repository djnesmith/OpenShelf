import Foundation
import Testing
@testable import OpenShelf

struct TextTransformsTests {
    @Test(arguments: [
        ("  hello  ", "hello"),
        ("\n\n\thello world\t\n", "hello world"),
        ("\u{00A0}café ☕️\u{00A0}", "café ☕️"),
        ("   ", ""),
        ("", ""),
        ("a\r\n", "a"),
    ])
    func trimStripsBothEndsOnly(input: String, expected: String) {
        #expect(TextTransforms.trim(input) == expected)
    }

    @Test func trimKeepsInnerSpacingAndLines() {
        #expect(TextTransforms.trim("  a  b\n\n c  ") == "a  b\n\n c")
    }

    @Test func trimLinesKeepsIndentationAndLineEndings() {
        #expect(TextTransforms.trimLines("  a  \n\tb\t\nc") == "  a\n\tb\nc")
        #expect(TextTransforms.trimLines("a  \r\nb \r\n") == "a\r\nb\r\n")
    }

    @Test func cleanUpNormalizesLineEndings() {
        #expect(TextTransforms.cleanUp("a\r\nb\rc") == "a\nb\nc")
    }

    @Test func cleanUpRemovesInvisiblesAndNonBreakingSpaces() {
        #expect(TextTransforms.cleanUp("zero\u{200B}width\u{FEFF}") == "zerowidth")
        #expect(TextTransforms.cleanUp("word\u{2060}joined") == "wordjoined")
        #expect(TextTransforms.cleanUp("a\u{00A0}b\u{202F}c") == "a b c")
    }

    @Test func cleanUpCollapsesInnerSpacesButKeepsIndentation() {
        #expect(TextTransforms.cleanUp("    let  x   =  1   ") == "    let x = 1")
        #expect(TextTransforms.cleanUp("\tif  a:") == "\tif a:")
    }

    @Test func cleanUpLeavesAtMostOneBlankLine() {
        #expect(TextTransforms.cleanUp("a\n\n\n\nb\n\nc") == "a\n\nb\n\nc")
        #expect(TextTransforms.cleanUp("a\n   \n\t\nb") == "a\n\nb")
    }

    @Test func cleanUpKeepsUnicodeIntact() {
        // The family emoji holds two U+200D joiners; the Persian word holds a U+200C non-joiner.
        let text = "naïve 👩‍👩‍👧 résumé — ok می\u{200C}خواهم"
        #expect(TextTransforms.cleanUp(text) == text)
    }

    @Test func dedentRemovesSharedIndentation() {
        #expect(TextTransforms.dedent("    a\n      b\n    c") == "a\n  b\nc")
        #expect(TextTransforms.dedent("\t\tx\n\t\ty") == "x\ny")
    }

    @Test func dedentIgnoresBlankLinesAndStopsAtMixedIndentation() {
        #expect(TextTransforms.dedent("    a\n\n    b") == "a\n\nb")
        #expect(TextTransforms.dedent("    a\n\tb") == "    a\n\tb")
        #expect(TextTransforms.dedent("a\n  b") == "a\n  b")
    }

    @Test func indentAndOutdentAreOneLevel() {
        #expect(TextTransforms.indent("a\n\nb") == "    a\n\n    b")
        #expect(TextTransforms.outdent("      a\n  b\n\tc\nd") == "  a\nb\nc\nd")
        #expect(TextTransforms.outdent(TextTransforms.indent("x\n  y")) == "x\n  y")
    }

    @Test func tabsAndSpacesConvertOnlyIndentation() {
        #expect(TextTransforms.tabsToSpaces("\tif x:\n\t\ty\ta") == "    if x:\n        y\ta")
        #expect(TextTransforms.spacesToTabs("        a\n      b\n  c") == "\t\ta\n\t  b\n  c")
    }

    @Test func tabsSpacesToolPicksTheDirectionFromTheText() {
        #expect(TextTool.tabsSpaces.apply(to: "\ta") == "    a")
        #expect(TextTool.tabsSpaces.apply(to: "    a") == "\ta")
    }

    @Test func straightenQuotesMakesASCII() {
        #expect(TextTransforms.straightenQuotes("“It’s” — ‘ok’…") == "\"It's\" -- 'ok'...")
        #expect(TextTransforms.straightenQuotes("plain \"text\"") == "plain \"text\"")
    }

    @Test func onlyPureToolsApplyInMemory() {
        for tool in TextTool.allCases {
            #expect((tool.apply(to: " x ") != nil) == tool.isPureSwift, "\(tool)")
        }
        #expect(!TextTool.reindent.isPureSwift)
        #expect(!TextTool.toMarkdown.isPureSwift)
    }
}
