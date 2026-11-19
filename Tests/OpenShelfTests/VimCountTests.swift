import Testing
@testable import OpenShelf

/// Counts in every position vim takes them, and the edges the widened vim
/// comparison found. Each expected result is what vim 9.2 gives (vim --clean,
/// shiftwidth=4 expandtab); keys separated by a space run as separate commands.
struct VimCountTests {
    static func run(_ start: String, _ keys: String) -> String {
        var engine = VimEngineTests.engine(start)
        for chunk in keys.split(separator: " ") {
            _ = engine.handle(VimEngineTests.keys(String(chunk)))
            _ = engine.handle(.escape)
        }
        return VimEngineTests.marked(engine)
    }

    @Test(arguments: [
        // counts in every position
        ("a\n|b\nc\nd\ne\nf\ng\nh", "3dj", "a\n|f\ng\nh"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "d3j", "a\n|f\ng\nh"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "2d3j", "|a"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "3dd", "a\n|e\nf\ng\nh"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "d3d", "a\n|e\nf\ng\nh"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", ">3j", "a\n    |b\n    c\n    d\n    e\nf\ng\nh"),
        ("|one two three four five", "c3wX<Esc>", "|X four five"),
        ("|one two three four five", "y2eP", "one tw|oone two three four five"),
        ("|one two three four five", "d2aw", "|three four five"),
        ("|axbxcxdx", "d3fx", "|dx"),
        ("|one two three four five", "gU3w", "|ONE TWO THREE four five"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "v3jd", "a\n|\nf\ng\nh"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "d2j .", "a\n|h"),
        ("a\n|b\nc\nd\ne\nf\ng\nh", "dj 3.", "a\n|h"),
        // counts inside a recorded macro (vim's results through feedkeys: normal! ignores q)
        ("|a b c d e f g h i j k l", "qad2wq@a", "|e f g h i j k l"),
        ("|a b c d e f g h i j k l m n o p q", "qa2d3wq2@a", "|"),
        ("|a\nb\nc\nd\ne\nf\ng\nh\ni\nj", "qad3jq@a", "|i\nj"),
        ("|a\nb\nc\nd\ne\nf\ng\nh", "qa3ddq.", "|g\nh"),
        ("|a b c d e f g h i j k l", "qad2wq3@a", "|i j k l"),
        // counted paragraph motions and objects past the text fail
        ("|a\n\nb", "d3}", "|a\n\nb"),
        ("a\n\n|b", "d3{", "a\n\n|b"),
        ("a\n|b\n\nc", "y3apP", "a\n|b\n\nc"),
        ("a\n\n|\nb\n", "y2ap", "a\n\n|\nb\n"),
        ("a\n\n|\n", "dap", "a\n\n|\n"),
        // {count}% is a percentage of the lines
        ("|a\nb\nc\nd", "d50%", "|c\nd"),
        ("|a\nb\nc\nd", "d101%", "|a\nb\nc\nd"),
        // word objects cross lines
        ("w|ord\n\n\nword2 w3\n", "c2iwZ<Esc>", "|Z\n\nword2 w3\n"),
        ("a\n|b\nc\nd", "d2aw", "a\n|d"),
        ("  x = f(a, b);\n | y\n", "d2aw", "  x = f(a, b);\n  y\n|"),
        ("|a b", "d999999iw", "a |b"),
        // operators with j, k, G and gg
        ("ab\nc|d\nef", "gUk", "A|B\nCD\nef"),
        ("ab\nc|d\nef", "2gUU", "ab\nC|D\nEF"),
        ("ab\nc|d\nef", "gUgg", "|AB\nCD\nef"),
        ("ab\nc|d\nef", "gUG", "ab\nC|D\nEF"),
        // $ with a count
        ("on|e two three", "d2$", "on|e two three"),
        ("a|b\ncd", "c3$Z<Esc>", "a|Z"),
        ("foo bar\n  |indented line\n\nlast", "d2$", "foo bar\n|last"),
        ("ab\n|\ncd", "$ k", "a|b\n\ncd"),
        ("ab\n|", "d2$ k", "a|b\n"),
        // e and w at the text's end
        ("x\n | y\n", "c3eZ<Esc>", "x\n |Z"),
        ("word\n|\n\nword2 w3\n", "c3eZ<Esc>", "word\n|Z"),
        ("|word\n\n", "c2wZ<Esc>", "|Z"),
        ("word\n|\n\n    word2 w3\n", "d2w", "word\n    |word2 w3\n"),
        ("a\nb\n|", "kyyj c3eZ<Esc> p", "a\nb\n|Z"),
        // b with a count near the start
        ("one| two", "d2B", "| two"),
        ("\n|\n", "d2b", "|\n\n"),
        // J
        ("(|a [b {c} d] e)", "3J", "|(a [b {c} d] e)"),
        ("x\na b |c", "3J", "x\n|a b c"),
        ("a\n|  \n\nb", "3J", "a\n  | b"),
        // brackets ahead of the cursor
        ("x|y (a) (b) (c)", "d2a(", "x|y (a) (b) (c)"),
        ("a|x\nfx gx (h (i) j) k", "d2a(", "ax\nfx gx (h | j) k"),
        ("a|b ()", "di(", "ab (|)"),
        ("a|b \"\"", "yi\"", "ab \"|\""),
        // yap, visual and > on blank lines
        ("x\n\na\nb|c", "yap", "x\n|\na\nbc"),
        ("ab|c\nd\ne", "v$jd", "ab|e"),
        ("abcdef|g\nd\ne", "vjjd", "abcde|f"),
        ("a\n|   \nb", ">j", "a\n      | \n    b"),
        ("|a\n\n\nb", "4J", "a| b"),

    ])
    func matchesVim(start: String, keys: String, expected: String) {
        #expect(Self.run(start, keys) == expected)
    }

    /// vim repeats a visual change with "."; this engine does not, so "." after one does
    /// nothing rather than repeat an older change.
    @Test func dotAfterAVisualChangeDoesNothing() {
        #expect(Self.run("|ab cd ef", "dw vld .") == "| ef")
    }
}
