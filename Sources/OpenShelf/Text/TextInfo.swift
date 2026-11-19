import CryptoKit
import Foundation

/// What Count and Hash report about a selection. Neither changes the text.
enum TextInfo {
    /// Words a minute for the reading time.
    static let wordsPerMinute = 230

    struct Counts: Equatable {
        var characters: Int
        var words: Int
        var lines: Int
        var sentences: Int

        /// Whole minutes, rounded up; 0 for text with no words.
        var readingMinutes: Int { (words + TextInfo.wordsPerMinute - 1) / TextInfo.wordsPerMinute }
    }

    /// Characters are what a person sees (an emoji with a skin tone is one).
    /// Words and sentences follow the system's rules for the language, so
    /// Chinese and Japanese count words without spaces. A final line break
    /// doesn't start another line.
    static func counts(_ text: String) -> Counts {
        Counts(
            characters: text.count,
            words: units(of: text, .byWords),
            lines: text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0),
            sentences: units(of: text, .bySentences)
        )
    }

    /// "142 words · 812 characters · 18 lines · 9 sentences · 1 min read"
    static func summary(_ counts: Counts) -> String {
        func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }
        var parts = [count(counts.words, "word"), count(counts.characters, "character"), count(counts.lines, "line"), count(counts.sentences, "sentence")]
        if counts.readingMinutes > 0 { parts.append("\(counts.readingMinutes) min read") }
        return parts.joined(separator: " · ")
    }

    private static func units(of text: String, _ options: String.EnumerationOptions) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: options.union(.substringNotRequired)) { _, range, _, _ in
            if !text[range].allSatisfy(\.isWhitespace) { count += 1 }
        }
        return count
    }

    enum Digest: CaseIterable {
        case md5, sha1, sha256

        var title: String {
            switch self {
            case .md5: "MD5"
            case .sha1: "SHA-1"
            case .sha256: "SHA-256"
            }
        }
    }

    /// The digest of the text's UTF-8 bytes, as lowercase hex.
    static func hash(_ text: String, _ digest: Digest) -> String {
        let data = Data(text.utf8)
        let bytes: [UInt8] = switch digest {
        case .md5: Array(Insecure.MD5.hash(data: data))
        case .sha1: Array(Insecure.SHA1.hash(data: data))
        case .sha256: Array(SHA256.hash(data: data))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
