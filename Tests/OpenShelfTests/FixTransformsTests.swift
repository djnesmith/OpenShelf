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
        // Comparison signs in prose are not tags.
        ("if x<y and y>z then done", "if x<y and y>z then done"),
        // A ">" inside a quoted attribute doesn't end the tag; source whitespace is one space.
        ("<a title=\"a>b\" href=\"x\">link</a>", "link"),
        ("<p>Hello\n        world</p>", "Hello world"),
        ("<p>&copy; 2026 &euro;5 &trade;</p>", "© 2026 €5 ™"),
    ])
    func htmlBecomesText(html: String, expected: String) {
        #expect(F.plainText(html) == expected)
    }

    @Test(arguments: [
        // Underscores are never emphasis: identifiers and links keep them.
        ("# Title\n\nSome **bold**, *em*, _kept_ and `code`.", "Title\n\nSome bold, em, _kept_ and code."),
        ("Call `__init__` or __init__, see https://e.com/_foo_ and >= 5", "Call __init__ or __init__, see https://e.com/_foo_ and >= 5"),
        ("```\n# install deps\n**not bold**\n```", "# install deps\n**not bold**"),
        ("[wiki](https://en.wikipedia.org/wiki/Foo_(bar)) after", "wiki after"),
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
        // The sentence's punctuation after a link stays.
        ("see https://x.com/p?id=1&utm_source=a.", "see https://x.com/p?id=1."),
        ("go https://x.com/p?utm_source=a, then", "go https://x.com/p, then"),
        // A link copied from HTML, with &amp; between parameters.
        ("href=\"https://x.com/p?id=1&amp;utm_source=a&amp;b=2\"", "href=\"https://x.com/p?id=1&amp;b=2\""),
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
        // Emoji, Chinese and Greek read wrongly, and mixed with correct words.
        // (你 is E4 BD A0, and A0 reads as a no-break space.)
        ("ðŸ˜€ ä½\u{00A0}å¥½ Î±Î²Î³", "😀 你好 αβγ"),
        ("cafÃ© café 😀 ’", "café café 😀 ’"),
        ("São pâte", "São pâte"),
    ])
    func misreadUTF8IsReadAgain(text: String, expected: String) {
        #expect(F.fixEncoding(text) == expected)
    }

    @Test(arguments: [
        ("\u{1B}[31mred\u{1B}[0m and \u{1B}[1;32mbold green\u{1B}[m", "red and bold green"),
        ("\u{1B}]0;title\u{07}prompt$ ", "prompt$ "),
        ("\u{1B}[2K\u{1B}[1Gline", "line"),
        ("no codes", "no codes"),
        ("\u{1B}(B\u{1B}[mreset", "reset"),
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
