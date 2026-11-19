import Foundation

/// A wedge search can find, from anywhere the open wheel leads.
struct WheelSearchCandidate: Hashable {
    let item: WheelItem
    /// The wheels it sits under, for the label: ["Lines", "Order"].
    var path: [String] = []

    /// "Sort Natural · Lines › Order".
    var label: String {
        path.isEmpty ? item.title : "\(item.title) · \(path.joined(separator: " › "))"
    }
}

/// Fuzzy search over a wheel's wedges: letters in order, not necessarily
/// together, scoring word starts and runs higher. Pure, so it is tested
/// without a wheel.
enum WheelSearch {
    /// The matches for `query`, best first. Ties go to the more recently
    /// used wedge (`recent`, newest first), then to catalogue order.
    static func results(for query: String, in candidates: [WheelSearchCandidate], recent: [WheelCommand] = []) -> [WheelSearchCandidate] {
        let scored = candidates.enumerated().compactMap { offset, candidate -> (WheelSearchCandidate, Int, Int)? in
            guard let score = score(query, candidate) else { return nil }
            return (candidate, score, offset)
        }
        func recency(_ candidate: WheelSearchCandidate) -> Int {
            recent.firstIndex(of: candidate.item.command) ?? Int.max
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let (ra, rb) = (recency(a.0), recency(b.0))
            if ra != rb { return ra < rb }
            return a.2 < b.2
        }.map(\.0)
    }

    /// A candidate's score: its title, or one of its keywords a little lower.
    /// Every word of the query has to match.
    static func score(_ query: String, _ candidate: WheelSearchCandidate) -> Int? {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let targets = [(candidate.item.title, 0)] + keywords(for: candidate.item.command).map { ($0, 3) }
        var total = 0
        for word in words {
            let best = targets.compactMap { target, penalty in score(word, in: fold(target)).map { $0 - penalty } }.max()
            guard let best else { return nil }
            total += best
        }
        return total
    }

    /// How well `query`'s letters, in order, match `text` (both folded), or
    /// nil if they don't all appear.
    static func score(_ query: String, in text: String) -> Int? {
        let query = Array(query), text = Array(text)
        guard !query.isEmpty else { return nil }
        // Jumping to word starts can skip past letters a plain match needs
        // ("ram" in "Frame Rate"), so try both ways and keep the better.
        let scores = [true, false].compactMap { score(query, in: text, preferWordStarts: $0) }
        return scores.max()
    }

    private static func score(_ query: [Character], in text: [Character], preferWordStarts: Bool) -> Int? {
        var score = 0
        var position = 0
        var previous = -2
        for letter in query {
            // Prefer the letter where a word starts, if it comes before the next plain one would.
            let plain = (position..<text.count).first { text[$0] == letter }
            guard let plain else { return nil }
            let wordStart = preferWordStarts ? (position..<text.count).first { text[$0] == letter && isWordStart(text, $0) } : nil
            let found = (wordStart != nil && plain != previous + 1) ? wordStart! : plain
            if found == previous + 1 { score += 5 }
            if isWordStart(text, found) { score += 8 }
            score -= min(found - position, 5)
            previous = found
            position = found + 1
        }
        if text.starts(with: query) { score += 15 }
        return score
    }

    /// Lower case without accents, so "e" finds "É" and "Ç".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func isWordStart(_ text: [Character], _ index: Int) -> Bool {
        index == 0 || !(text[index - 1].isLetter || text[index - 1].isNumber)
    }

    /// Other words people type for a wedge.
    static func keywords(for command: WheelCommand) -> [String] {
        switch command {
        case .text(.tool(let tool)): textKeywords[tool] ?? []
        case .text(.convert(let format)): [format.title, format.fileExtension]
        case .text(.edit): ["vim", "editor", "window"]
        case .convert(let format): [format.fileExtension, format == .jpg ? "jpeg" : nil, format == .md ? "markdown" : nil].compactMap { $0 }
        case .text, .action, .tool: []
        }
    }

    static let textKeywords: [TextTool: [String]] = [
        .trim: ["whitespace", "strip"],
        .cleanUp: ["tidy", "clean"],
        .reindent: ["format", "pretty", "beautify"],
        .toMarkdown: ["markdown", "md"],
        .dedent: ["unindent"],
        .trimLines: ["trailing whitespace"],
        .straightenQuotes: ["smart quotes", "ascii"],
        .sortAZ: ["sort", "alphabetical", "order"],
        .sortNatural: ["sort", "numbers"],
        .sortByLength: ["sort", "length"],
        .reverseLines: ["reverse", "flip"],
        .shuffleLines: ["random", "shuffle"],
        .removeDuplicates: ["dedupe", "unique", "uniq", "duplicates"],
        .removeBlankLines: ["empty lines", "blank"],
        .numberLines: ["numbered", "ordered list"],
        .markdownList: ["bullets", "list"],
        .markdownTable: ["csv", "tsv", "table"],
        .joinWithCommas: ["join", "comma", "csv"],
        .joinWithSpaces: ["join", "one line"],
        .splitAtCommas: ["split", "comma"],
        .splitAtSpaces: ["split", "words"],
        .quoteLines: ["quote", "string"],
        .unquoteLines: ["unquote"],
        .addCommas: ["comma", "trailing comma"],
        .upperCase: ["uppercase", "caps", "capitals"],
        .lowerCase: ["lowercase", "small"],
        .titleCase: ["title", "capitalise", "capitalize"],
        .sentenceCase: ["sentence"],
        .camelCase: ["camel"],
        .pascalCase: ["pascal", "upper camel"],
        .snakeCase: ["snake", "underscore"],
        .kebabCase: ["kebab", "dash", "hyphen"],
        .constantCase: ["constant", "screaming", "upper snake"],
        .plainText: ["html", "markdown", "strip formatting", "remove tags", "text only"],
        .stripTracking: ["utm", "fbclid", "gclid", "clean link", "url"],
        .fixEncoding: ["mojibake", "utf-8", "utf8", "garbled", "latin-1"],
        .stripANSI: ["ansi", "escape codes", "colour", "color", "terminal"],
        .encodeURL: ["encode", "percent", "escape url"], .decodeURL: ["decode", "percent", "unescape url"],
        .encodeBase64: ["encode", "b64"], .decodeBase64: ["decode", "b64"],
        .encodeHTML: ["encode", "entities", "escape html"], .decodeHTML: ["decode", "entities", "unescape html"],
        .encodeJSON: ["encode", "escape", "quote json"], .decodeJSON: ["decode", "unescape json"],
        .encodeHex: ["encode", "bytes"], .decodeHex: ["decode", "bytes"],
        .encodeUnicode: ["encode", "escape", "\\u"], .decodeUnicode: ["decode", "unescape", "\\u"],
        .uuid: ["guid", "generate", "id"], .timestamp: ["now", "date", "iso 8601", "generate"],
        .loremIpsum: ["placeholder", "dummy text", "generate"], .password: ["random", "generate", "secret"],
        .jwt: ["token", "json web token", "bearer"],
        .extractLinks: ["urls", "extract", "find links"], .extractEmails: ["addresses", "extract", "mail"],
        .extractNumbers: ["digits", "extract", "figures"], .extractPhoneNumbers: ["phones", "extract", "tel"],
        .extractDates: ["extract", "when", "times"],
        .count: ["words", "characters", "length", "lines", "reading time"],
        .md5: ["hash", "checksum", "digest"],
        .sha1: ["hash", "checksum", "digest", "sha1"],
        .sha256: ["hash", "checksum", "digest", "sha256"],
    ]
}

/// What has been typed into the wheel's search, and whether it is all
/// selected (after ⌘F), so the next letter replaces it.
struct WheelSearchQuery: Equatable {
    private(set) var text = ""
    private(set) var isAllSelected = false

    var isEmpty: Bool { text.isEmpty }

    mutating func type(_ characters: String) {
        text = isAllSelected ? characters : text + characters
        isAllSelected = false
    }

    /// Deletes the last character, or all of it when selected.
    mutating func deleteBackward() {
        if isAllSelected { text = "" } else if !text.isEmpty { text.removeLast() }
        isAllSelected = false
    }

    mutating func selectAll() {
        isAllSelected = !text.isEmpty
    }

    /// Whether typing `characters` adds to a search: letters, digits and a
    /// few marks that appear in tool names. Starting one needs a letter or digit.
    static func accepts(_ characters: String, starting: Bool) -> Bool {
        guard characters.count == 1, let character = characters.first else { return false }
        if character.isLetter || character.isNumber { return true }
        return !starting && " -_.→".contains(character)
    }
}
