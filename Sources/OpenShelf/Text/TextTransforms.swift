import Foundation

/// The text wheel's pure-Swift tools. Each takes the selected text and returns
/// the replacement; none touches a file or a process.
enum TextTransforms {
    /// Spaces per level for Indent, Outdent and the tab conversions.
    static let indentWidth = 4

    /// Whitespace and line breaks off both ends of the whole text.
    static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trailing whitespace off every line; indentation is kept.
    static func trimLines(_ text: String) -> String {
        mapLines(text) { stripTrailing($0) }
    }

    /// Tidies text pasted from the web or a document without touching
    /// indentation: CRLF and CR become LF, invisible characters go,
    /// non-breaking spaces become spaces, runs of spaces inside a line become
    /// one, trailing whitespace goes, and three or more blank lines become one.
    static func cleanUp(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        normalized.unicodeScalars.removeAll { invisible.contains($0) }
        normalized = String(String.UnicodeScalarView(normalized.unicodeScalars.map { nonBreakingSpaces.contains($0) ? " " : $0 }))

        var lines: [String] = []
        var blankRun = 0
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let cleaned = collapseInnerSpaces(stripTrailing(String(line)))
            if cleaned.isEmpty {
                blankRun += 1
                if blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            lines.append(cleaned)
        }
        return lines.joined(separator: "\n")
    }

    /// Removes the indentation every non-blank line shares, so code copied
    /// from deep inside a file starts at the left edge.
    static func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let indents = lines.filter { !isBlank($0) }.map(leadingWhitespace)
        guard var common = indents.first else { return text }
        for indent in indents.dropFirst() {
            common = String(zip(common, indent).prefix { $0 == $1 }.map(\.0))
        }
        guard !common.isEmpty else { return text }
        return lines.map { $0.hasPrefix(common) ? String($0.dropFirst(common.count)) : stripTrailing($0) }.joined(separator: "\n")
    }

    /// One level more on every non-blank line.
    static func indent(_ text: String) -> String {
        let pad = String(repeating: " ", count: indentWidth)
        return mapLines(text) { isBlank($0) ? $0 : pad + $0 }
    }

    /// One level less on every line: a tab, or up to `indentWidth` spaces.
    static func outdent(_ text: String) -> String {
        mapLines(text) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, indentWidth)))
        }
    }

    /// Each tab in the indentation becomes `indentWidth` spaces. Tabs after
    /// the first non-blank character are left alone (they may be data).
    static func tabsToSpaces(_ text: String) -> String {
        mapLines(text) { line in
            let indent = leadingWhitespace(line)
            let spaces = indent.replacingOccurrences(of: "\t", with: String(repeating: " ", count: indentWidth))
            return spaces + line.dropFirst(indent.count)
        }
    }

    /// Each `indentWidth` spaces of indentation become a tab; leftover spaces stay.
    static func spacesToTabs(_ text: String) -> String {
        mapLines(text) { line in
            let indent = leadingWhitespace(line)
            let width = indent.reduce(0) { $0 + ($1 == "\t" ? indentWidth : 1) }
            let converted = String(repeating: "\t", count: width / indentWidth) + String(repeating: " ", count: width % indentWidth)
            return converted + line.dropFirst(indent.count)
        }
    }

    /// Curly quotes, primes, dashes and the ellipsis become plain ASCII.
    static func straightenQuotes(_ text: String) -> String {
        var result = ""
        for character in text {
            result += straight[character] ?? String(character)
        }
        return result
    }

    // MARK: Helpers

    /// Zero-width space, word joiner and byte-order mark. The zero-width
    /// joiner and non-joiner stay: emoji sequences and some scripts need them.
    static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{2060}", "\u{FEFF}"]
    static let nonBreakingSpaces: Set<Unicode.Scalar> = ["\u{00A0}", "\u{202F}", "\u{2007}"]
    static let straight: [Character: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
        "\u{2013}": "-", "\u{2014}": "--", "\u{2026}": "...",
    ]

    private static func mapLines(_ text: String, _ transform: (String) -> String) -> String {
        text.components(separatedBy: "\n").map(transform).joined(separator: "\n")
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
    }

    static func leadingWhitespace(_ line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// Trailing spaces and tabs off one line. A CR at the end (from a CRLF
    /// line kept by `components`) stays, so Trim Lines keeps line endings.
    private static func stripTrailing(_ line: String) -> String {
        let hasCR = line.hasSuffix("\r")
        var body = hasCR ? String(line.dropLast()) : line
        while let last = body.last, last == " " || last == "\t" { body.removeLast() }
        return hasCR ? body + "\r" : body
    }

    /// Runs of spaces after the indentation become one space.
    private static func collapseInnerSpaces(_ line: String) -> String {
        let indent = leadingWhitespace(line)
        var result = indent
        var previousWasSpace = false
        for character in line.dropFirst(indent.count) {
            if character == " " {
                if previousWasSpace { continue }
                previousWasSpace = true
            } else {
                previousWasSpace = false
            }
            result.append(character)
        }
        return result
    }
}
