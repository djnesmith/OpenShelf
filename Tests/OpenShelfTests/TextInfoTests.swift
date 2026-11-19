import Testing
@testable import OpenShelf

struct TextInfoTests {
    @Test(arguments: [
        ("", TextInfo.Counts(characters: 0, words: 0, lines: 0, sentences: 0)),
        ("   \n\n", TextInfo.Counts(characters: 5, words: 0, lines: 2, sentences: 0)),
        ("Hello world.", TextInfo.Counts(characters: 12, words: 2, lines: 1, sentences: 1)),
        ("One. Two? Three!\n", TextInfo.Counts(characters: 17, words: 3, lines: 1, sentences: 3)),
        ("a\n\nb", TextInfo.Counts(characters: 4, words: 2, lines: 3, sentences: 2)),
        // One emoji with a skin tone is one character.
        ("👋🏽 hi", TextInfo.Counts(characters: 4, words: 1, lines: 1, sentences: 1)),
        // No spaces between Japanese words, and they still count.
        ("今日は良い天気です。", TextInfo.Counts(characters: 10, words: 5, lines: 1, sentences: 1)),
    ])
    func counts(text: String, expected: TextInfo.Counts) {
        #expect(TextInfo.counts(text) == expected)
    }

    @Test func readingTimeRoundsUpAndIsLeftOutForNoWords() {
        #expect(TextInfo.Counts(characters: 0, words: 0, lines: 0, sentences: 0).readingMinutes == 0)
        #expect(TextInfo.Counts(characters: 0, words: 1, lines: 0, sentences: 0).readingMinutes == 1)
        #expect(TextInfo.Counts(characters: 0, words: 230, lines: 0, sentences: 0).readingMinutes == 1)
        #expect(TextInfo.Counts(characters: 0, words: 231, lines: 0, sentences: 0).readingMinutes == 2)
        #expect(TextInfo.summary(TextInfo.counts("")) == "0 words · 0 characters · 0 lines · 0 sentences")
        #expect(TextInfo.summary(TextInfo.counts("Hi.")) == "1 word · 3 characters · 1 line · 1 sentence · 1 min read")
    }

    /// The published test vectors for "abc" and "", plus one non-ASCII
    /// character, so the bytes hashed are UTF-8.
    @Test func hashesMatchKnownDigests() {
        #expect(TextInfo.hash("abc", .md5) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(TextInfo.hash("abc", .sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(TextInfo.hash("abc", .sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(TextInfo.hash("", .sha256) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(TextInfo.hash("é", .md5) == "66ddcd97cfdeabb2f6fb8a999b4bc76f")
        #expect(TextInfo.hash("é", .sha256) == "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c")
        #expect(TextInfo.Digest.allCases.map(\.title) == ["MD5", "SHA-1", "SHA-256"])
    }
}
