import Foundation

/// The Case tools: each takes the selected text and returns the replacement.
enum CaseTransforms {
    static func upper(_ text: String) -> String { text.uppercased() }

    static func lower(_ text: String) -> String { text.lowercased() }

    /// Every word starts with a capital. A word that already has a capital
    /// after its first letter ("iPhone", "NASA") is left as it is, unless
    /// the whole text is capitals, which are lowered first. No small-word
    /// rule ("Of", "The" are capitalised too).
    static func title(_ text: String) -> String {
        let base = text.contains(where: \.isLowercase) ? Array(text) : Array(text.lowercased())
        var result = ""
        var index = 0
        while index < base.count {
            // A word: letters and digits, with apostrophes only between letters.
            var end = index
            while end < base.count, base[end].isLetter || base[end].isNumber
                || (isApostrophe(base[end]) && end > index && end + 1 < base.count && base[end + 1].isLetter) {
                end += 1
            }
            guard end > index else {
                result.append(base[index])
                index += 1
                continue
            }
            let word = base[index..<end]
            if word.dropFirst().contains(where: \.isUppercase) || !(word.first?.isLetter ?? false) {
                result += String(word)
            } else {
                result += word.first!.uppercased() + String(word.dropFirst())
            }
            index = end
        }
        return result
    }

    /// Lower case, with a capital to start the text, each sentence (after
    /// . ! or ? and a space) and each paragraph (after a blank line).
    static func sentence(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        var previous: Character? = nil
        var newlinesInARow = 0
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                result += capitalizeNext ? character.uppercased() : String(character)
                capitalizeNext = false
                newlinesInARow = 0
            } else {
                result.append(character)
                if character.isNewline {
                    newlinesInARow += 1
                    if newlinesInARow >= 2 { capitalizeNext = true }
                } else if !character.isWhitespace {
                    newlinesInARow = 0
                }
                if character.isWhitespace, let previous, [".", "!", "?"].contains(previous) { capitalizeNext = true }
            }
            previous = character
        }
        return result
    }

    static func camel(_ text: String) -> String {
        identifier(text) { words in
            (words.first.map { $0.lowercased() } ?? "") + words.dropFirst().map(capitalizedWord).joined()
        }
    }

    static func pascal(_ text: String) -> String {
        identifier(text) { $0.map(capitalizedWord).joined() }
    }

    static func snake(_ text: String) -> String {
        identifier(text) { $0.map { $0.lowercased() }.joined(separator: "_") }
    }

    static func kebab(_ text: String) -> String {
        identifier(text) { $0.map { $0.lowercased() }.joined(separator: "-") }
    }

    static func constant(_ text: String) -> String {
        identifier(text) { $0.map { $0.uppercased() }.joined(separator: "_") }
    }

    /// The words of an identifier or a phrase: split at anything that isn't
    /// a letter or digit, at a lower-to-upper change ("fooBar"), after a
    /// digit before a capital ("v2Update"), and before the last capital of
    /// an acronym ("HTTPServer" is HTTP, Server).
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if let previous = current.last, character.isUppercase {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let afterLowerOrDigit = previous.isLowercase || previous.isNumber
                let endsAcronym = previous.isUppercase && (next?.isLowercase ?? false)
                if afterLowerOrDigit || endsAcronym {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: Helpers

    /// Each line on its own, keeping its indentation and trailing spaces, so
    /// a list of names stays a list.
    private static func identifier(_ text: String, _ build: ([String]) -> String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.map { line in
            let words = words(line)
            guard !words.isEmpty else { return line }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let trailing = line.reversed().prefix { $0 == " " || $0 == "\t" }
            return indent + build(words) + String(trailing.reversed())
        })
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "\u{2019}"
    }

    private static func capitalizedWord(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }
}
