import Testing
@testable import OpenShelf

struct FixTransformsTests {
    typealias F = FixTransforms

    @Test(arguments: [
        ("<p>Hello <b>world</b>.</p><p>Next&nbsp;one &amp; &lt;two&gt;</p>", "Hello world.\n\nNext one & <two>"),
        ("a<br>b<br/>c", "a\nb\nc"),
        ("<ul><li>one</li><li>two</li></ul>", "• one\n\n• two"),
        ("<style>p{color:red}</style><script>alert(1)</script><p>kept</p>", "kept"),
        ("caf&#233; &#x2014; &amp;lt;", "café — &lt;"),
        ("<!-- note --><span>x</span>", "x"),
    ])
    func htmlBecomesText(html: String, expected: String) {
        #expect(F.plainText(html) == expected)
    }

    @Test(arguments: [
        ("# Title\n\nSome **bold**, _em_ and `code`.", "Title\n\nSome bold, em and code."),
        ("> quoted [link](https://x.y) and ![pic](a.png)", "quoted link and pic"),
        ("```swift\nlet x = 1\n```", "let x = 1"),
        ("- item *one*\n- item ~~two~~", "- item one\n- item two"),
        // Underscores and stars inside words are left alone.
        ("snake_case_name and 2*3*4", "snake_case_name and 2*3*4"),
        ("plain text stays", "plain text stays"),
    ])
    func markdownBecomesText(markdown: String, expected: String) {
        #expect(F.plainText(markdown) == expected)
    }

    @Test(arguments: [
        ("see https://a.com/p?utm_source=x&utm_medium=y&id=7#top now", "see https://a.com/p?id=7#top now"),
        ("https://a.com/?fbclid=abc", "https://a.com/"),
        ("(https://a.com/x?gclid=1&q=two)", "(https://a.com/x?q=two)"),
        ("https://a.com/x?MC_EID=1&Keep=1", "https://a.com/x?Keep=1"),
        ("no links here, utm_source=x", "no links here, utm_source=x"),
        ("https://a.com/x?q=1", "https://a.com/x?q=1"),
    ])
    func trackingParametersGo(text: String, expected: String) {
        #expect(F.stripTracking(text) == expected)
    }

    @Test(arguments: [
        ("cafÃ©", "café"),
        ("itâ€™s â€œquotedâ€\u{9D}", "it’s “quoted”"),
        ("naÃ¯ve rÃ©sumÃ©", "naïve résumé"),
        // Already right, or plain ASCII: unchanged.
        ("café", "café"),
        ("plain", "plain"),
        // A real "Ã" in correct text that doesn't decode stays.
        ("Ã alone", "Ã alone"),
    ])
    func misreadUTF8IsReadAgain(text: String, expected: String) {
        #expect(F.fixEncoding(text) == expected)
    }

    @Test(arguments: [
        ("\u{1B}[31mred\u{1B}[0m and \u{1B}[1;32mbold green\u{1B}[m", "red and bold green"),
        ("\u{1B}]0;title\u{07}prompt$ ", "prompt$ "),
        ("\u{1B}[2K\u{1B}[1Gline", "line"),
        ("no codes", "no codes"),
    ])
    func ansiCodesGo(text: String, expected: String) {
        #expect(F.stripANSI(text) == expected)
    }

    @Test func emptyTextStaysEmpty() {
        for tool in [TextTool.plainText, .stripTracking, .fixEncoding, .stripANSI] {
            #expect(tool.apply(to: "") == "", "\(tool)")
        }
    }
}
