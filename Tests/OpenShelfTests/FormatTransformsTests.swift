import Foundation
import Testing
@testable import OpenShelf

struct FormatTransformsTests {
    typealias F = FormatTransforms

    @Test(arguments: [
        (F.Wrapper.quotes, "hi", "\"hi\""),
        (.parentheses, "a b\n", "(a b)\n"),
        (.brackets, "x", "[x]"),
        (.braces, "x", "{x}"),
        (.codeFence, "let a = 1\nlet b = 2\n", "```\nlet a = 1\nlet b = 2\n```\n"),
        (.blockQuote, "one\n\ntwo", "> one\n>\n> two"),
    ])
    func wraps(wrapper: F.Wrapper, text: String, expected: String) {
        #expect(F.wrap(text, in: wrapper) == expected)
    }

    @Test func markdownLinkNeedsACopiedLink() {
        #expect(F.markdownLink(" the docs ", link: "https://a.com/x") == "[the docs](https://a.com/x)")
        #expect(F.markdownLink("a]b", link: "mailto:me@x.io") == "[a\\]b](mailto:me@x.io)")
        #expect(F.markdownLink("x", link: "not a link") == nil)
        #expect(F.markdownLink("x", link: "ftp://a.com") == nil)
        #expect(F.markdownLink("x", link: nil) == nil)
    }

    @Test func alignsATable() {
        let table = "|a|bb|\n|:-|-:|\n|ccc|d|\nnot a row"
        #expect(F.alignTable(table) == "| a   | bb  |\n| :-- | --: |\n| ccc | d   |\nnot a row")
        #expect(F.alignTable("no table here") == "no table here")
    }

    @Test func headingsGoUpAndDown() {
        #expect(F.heading("## A\ntext\n# B\n####### seven", up: true) == "# A\ntext\n# B\n####### seven")
        #expect(F.heading("# A\n###### six\n#nospace", up: false) == "## A\n###### six\n#nospace")
    }

    @Test func datesConvert() throws {
        let ny = try #require(TimeZone(identifier: "America/New_York"))
        #expect(F.convertDate("1763553600", timeZone: ny) == "2025-11-19T07:00:00-05:00")
        #expect(F.convertDate("1763553600000\n", timeZone: ny) == "2025-11-19T07:00:00-05:00")
        #expect(F.convertDate("2025-11-19T07:00:00-05:00", timeZone: ny) == "1763553600")
        #expect(F.convertDate("2025-11-19T12:00:00.250Z", timeZone: ny) == "1763553600")
        #expect(F.convertDate("not a date", timeZone: ny) == "not a date")
        #expect(F.convertDate("12345", timeZone: ny) == "12345")
        // A date inside a sentence is left alone: only a selection that is all date converts.
        #expect(F.convertDate("Meet on November 19, 2025 please", timeZone: ny) == "Meet on November 19, 2025 please")
        // A date in words, whole: becomes ISO 8601.
        #expect(F.convertDate("November 19, 2025 at 7:00 AM", timeZone: ny).hasPrefix("2025-11-19T"))
    }
}
