import Foundation

/// `:s` for the Edit window (ROADMAP C12 item 1): parsing `:[range]s/pattern/replacement/[flags]`
/// and turning vim's pattern and replacement syntax into ICU regular expressions. Pure.
enum VimSubstitute {
    enum Range: Equatable {
        case current
        case all
        /// 1-based first and last line; `$` is resolved by the engine.
        case lines(Bound, Bound)
        case visual
    }

    enum Bound: Equatable {
        case number(Int)
        case current
        case last
    }

    struct Command: Equatable {
        var range: Range
        /// Empty: the last pattern used.
        var pattern: String
        var replacement: String
        var global: Bool
        /// nil: smartcase, as `/` does; true for `i`, false for `I`.
        var ignoreCase: Bool?
    }

    /// The command in `line` (what follows ":"), or nil when it isn't a substitute.
    static func parse(_ line: String) -> Command? {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        let range: Range
        if rest.hasPrefix("%") {
            range = .all
            rest = rest.dropFirst()
        } else if rest.hasPrefix("'<,'>") {
            range = .visual
            rest = rest.dropFirst(5)
        } else if let (first, afterFirst) = bound(rest) {
            rest = afterFirst
            if rest.hasPrefix(","), let (second, afterSecond) = bound(rest.dropFirst()) {
                range = .lines(first, second)
                rest = afterSecond
            } else {
                range = .lines(first, first)
            }
        } else {
            range = .current
        }
        guard rest.hasPrefix("s") else { return nil }
        rest = rest.dropFirst()
        // "substitute" spelled out, or a bare :s.
        if rest.hasPrefix("ubstitute") { rest = rest.dropFirst(9) }
        guard let delimiter = rest.first else { return Command(range: range, pattern: "", replacement: "~", global: false, ignoreCase: nil) }
        guard !delimiter.isLetter, !delimiter.isNumber, delimiter != "\\", delimiter != "\"", delimiter != "|", !delimiter.isWhitespace else { return nil }
        rest = rest.dropFirst()
        let parts = split(rest, on: delimiter)
        let pattern = parts.first ?? ""
        let replacement = parts.count > 1 ? parts[1] : ""
        let flags = parts.count > 2 ? parts[2] : ""
        guard flags.allSatisfy({ "giI&".contains($0) }) else { return nil }
        let ignore: Bool? = flags.contains("I") ? false : flags.contains("i") ? true : nil
        return Command(range: range, pattern: pattern, replacement: replacement, global: flags.contains("g"), ignoreCase: ignore)
    }

    private static func bound(_ text: Substring) -> (Bound, Substring)? {
        if text.hasPrefix(".") { return (.current, text.dropFirst()) }
        if text.hasPrefix("$") { return (.last, text.dropFirst()) }
        let digits = text.prefix(while: \.isNumber)
        guard let number = Int(digits) else { return nil }
        return (.number(number), text.dropFirst(digits.count))
    }

    /// Splits at unescaped `delimiter`s, keeping other escapes; "\/" becomes "/".
    private static func split(_ text: Substring, on delimiter: Character) -> [String] {
        var parts = [""]
        var escaped = false
        for character in text {
            if escaped {
                if character != delimiter { parts[parts.count - 1].append("\\") }
                parts[parts.count - 1].append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == delimiter {
                parts.append("")
            } else {
                parts[parts.count - 1].append(character)
            }
        }
        if escaped { parts[parts.count - 1].append("\\") }
        return parts
    }

    /// Vim's "magic" pattern as an ICU pattern: `\(` `\)` `\|` `\+` `\?` `\=` `\{n,m}` and
    /// `\<` `\>` become ICU's, and characters special only to ICU are escaped. `\c` and `\C`
    /// anywhere ask for case to be ignored or matched.
    static func icuPattern(_ vim: String) -> (pattern: String, caseOverride: Bool?) {
        var out = ""
        var caseOverride: Bool?
        var characters = Array(vim)
        var index = 0
        var inBraces = false
        func next() -> Character? { index < characters.count ? characters[index] : nil }
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "\\", let escaped = next() {
                index += 1
                switch escaped {
                case "(", ")", "|", "+", "?": out.append(escaped)
                case "=": out.append("?")
                case "{": out.append("{"); inBraces = true
                case "}": out.append("}"); inBraces = false
                case "<", ">": out += "\\b"
                case "c": caseOverride = true
                case "C": caseOverride = false
                case "s", "S", "d", "D", "w", "W", "n", "t", ".", "*", "[", "]", "^", "$", "/", "\\": out += "\\\(escaped)"
                default: out.append(escaped)
                }
            } else if inBraces, character == "}" {
                out.append("}")
                inBraces = false
            } else if "()|+?{}".contains(character) {
                out += "\\\(character)"
            } else {
                out.append(character)
            }
        }
        characters.removeAll()
        return (out, caseOverride)
    }

    /// Vim's replacement as an NSRegularExpression template: `&` and `\0` the match, `\1`…
    /// `\9` the groups, `\r` a line break, `\t` a tab, `\&` `\\` and `$` themselves.
    static func template(_ vim: String) -> String {
        var out = ""
        var characters = vim.makeIterator()
        while let character = characters.next() {
            switch character {
            case "&": out += "$0"
            case "$": out += "\\$"
            case "\\":
                guard let escaped = characters.next() else { out += "\\\\"; continue }
                switch escaped {
                case "0"..."9": out += "$\(escaped)"
                case "r", "n": out += "\n"
                case "t": out += "\t"
                case "&": out += "&"
                case "\\": out += "\\\\"
                default: out.append(escaped)
                }
            default:
                out.append(character)
            }
        }
        return out
    }
}
