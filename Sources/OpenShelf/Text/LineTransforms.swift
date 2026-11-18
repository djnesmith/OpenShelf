import Foundation

/// Text as lines, keeping what a tool must put back: the line ending and a
/// newline at the end. CRLF, LF, a lone CR (Word's paragraph mark) and
/// U+2028 (a soft line break) all end a line; the result uses the first of
/// those the text has, so mixed endings come back as one kind.
struct LineText {
    var lines: [String]
    var separator: String
    var endsWithNewline: Bool

    init(_ text: String) {
        separator = ["\r\n", "\r", "\u{2028}"].first { text.contains($0) } ?? "\n"
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .components(separatedBy: "\n")
        endsWithNewline = lines.count > 1 && lines.last == ""
        if endsWithNewline { lines.removeLast() }
        self.lines = text.isEmpty ? [] : lines
    }

    var text: String {
        lines.joined(separator: separator) + (endsWithNewline && !lines.isEmpty ? separator : "")
    }

    /// The same endings around new lines.
    func with(_ lines: [String]) -> String {
        var copy = self
        copy.lines = lines
        return copy.text
    }
}

/// The Lines tools: each takes the selected text and returns the replacement.
enum LineTransforms {
    /// A to Z, ignoring case. Lines that compare equal keep their order.
    static func sortAZ(_ text: String) -> String {
        stableSort(text) { $0.localizedCaseInsensitiveCompare($1) }
    }

    /// As Finder sorts: numbers by value ("file 2" before "file 10"), case ignored.
    static func sortNatural(_ text: String) -> String {
        stableSort(text) { $0.localizedStandardCompare($1) }
    }

    /// Shortest first. Lines of the same length keep their order.
    static func sortByLength(_ text: String) -> String {
        stableSort(text) { a, b in
            a.count == b.count ? .orderedSame : (a.count < b.count ? .orderedAscending : .orderedDescending)
        }
    }

    static func reverse(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.reversed())
    }

    static func shuffle(_ text: String) -> String {
        var generator = SystemRandomNumberGenerator()
        return shuffle(text, using: &generator)
    }

    /// A new order whenever there is one, so a shuffle never answers
    /// "Nothing to change" by chance.
    static func shuffle(_ text: String, using generator: inout some RandomNumberGenerator) -> String {
        let lines = LineText(text)
        guard Set(lines.lines).count > 1 else { return text }
        var shuffled = lines.lines
        repeat { shuffled.shuffle(using: &generator) } while shuffled == lines.lines
        return lines.with(shuffled)
    }

    /// Exact repeats go; the first of each stays where it was.
    static func removeDuplicates(_ text: String) -> String {
        let lines = LineText(text)
        var seen: Set<String> = []
        return lines.with(lines.lines.filter { seen.insert($0).inserted })
    }

    static func removeBlankLines(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.filter { !isBlank($0) })
    }

    /// "1. " before each non-blank line, after its indentation; blank lines
    /// stay unnumbered. Lines already numbered this way are renumbered.
    static func number(_ text: String) -> String {
        let lines = LineText(text)
        var count = 0
        return lines.with(lines.lines.map { line in
            guard !isBlank(line) else { return line }
            count += 1
            let indent = leadingWhitespace(line)
            var body = Substring(line.dropFirst(indent.count))
            let digits = body.prefix(while: \.isASCII).prefix(while: \.isNumber)
            if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") { body = body.dropFirst(digits.count + 2) }
            return "\(indent)\(count). \(body)"
        })
    }

    /// "- " before each non-blank line, after its indentation, so nesting
    /// stays. Lines that are already list items are left alone.
    static func markdownList(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.map { line in
            let indent = leadingWhitespace(line)
            let body = line.dropFirst(indent.count)
            guard !body.isEmpty, !["- ", "* ", "+ "].contains(where: body.hasPrefix) else { return line }
            return indent + "- " + body
        })
    }

    /// The non-blank lines, trimmed, on one line with `separator` between.
    /// A newline at the end stays, so the next line isn't pulled up.
    static func join(_ text: String, with separator: String) -> String {
        let lines = LineText(text)
        let joined = lines.lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
        return lines.with(joined.isEmpty ? [] : [joined])
    }

    /// Each line cut at `delimiter`; the pieces, trimmed, one per line.
    /// Blank lines stay, so paragraphs stay apart.
    static func split(_ text: String, at delimiter: Character) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.flatMap { line in
            isBlank(line) ? [line] : line.split(separator: delimiter).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        })
    }

    /// Each line cut at runs of spaces and tabs, one word per line. Blank
    /// lines stay.
    static func splitAtSpaces(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.flatMap { line in
            isBlank(line) ? [line] : line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        })
    }

    /// Each non-blank line in double quotes, after its indentation, with `\`
    /// and `"` escaped, so the lines can go into code.
    static func quote(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.map { line in
            guard !isBlank(line) else { return line }
            let indent = leadingWhitespace(line)
            let body = line.dropFirst(indent.count)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return indent + "\"" + body + "\""
        })
    }

    /// Takes the quotes off lines that are one quoted string: they start and
    /// end with the same quote (an ending comma may follow) and hold no other
    /// closing quote. Double quotes also lose their escapes.
    static func unquote(_ text: String) -> String {
        let lines = LineText(text)
        return lines.with(lines.lines.map { line in
            let indent = leadingWhitespace(line)
            var body = Substring(line.dropFirst(indent.count))
            while let last = body.last, last == " " || last == "\t" { body.removeLast() }
            let comma = body.hasSuffix(",") ? "," : ""
            if !comma.isEmpty { body.removeLast() }
            guard body.count >= 2, let quote = body.first, quote == "\"" || quote == "'", body.last == quote else { return line }
            let inner = String(body.dropFirst().dropLast())
            guard isOneString(inner, quote: quote) else { return line }
            return indent + (quote == "\"" ? unescape(inner) : inner) + comma
        })
    }

    /// A comma at the end of every non-blank line but the last, for lists
    /// in code. Lines that already end with one are left alone.
    static func addCommas(_ text: String) -> String {
        let lines = LineText(text)
        guard let last = lines.lines.lastIndex(where: { !isBlank($0) }) else { return text }
        return lines.with(lines.lines.enumerated().map { index, line in
            guard index < last, !isBlank(line) else { return line }
            var body = line
            while let end = body.last, end == " " || end == "\t" { body.removeLast() }
            return body.hasSuffix(",") ? line : body + ","
        })
    }

    /// CSV or TSV (tab if the first line has one) as a Markdown table, the
    /// first row as its header. Short rows are padded; `|` is escaped.
    static func markdownTable(_ text: String) -> String {
        let shape = LineText(text)
        let firstLine = shape.lines.first ?? ""
        let rows = parseDelimited(text, delimiter: firstLine.contains("\t") ? "\t" : ",")
        guard let header = rows.first else { return text }
        let width = rows.map(\.count).max() ?? header.count
        func row(_ cells: [String]) -> String {
            let padded = cells + Array(repeating: "", count: width - cells.count)
            return "| " + padded.map(tableCell).joined(separator: " | ") + " |"
        }
        let separatorRow = "|" + Array(repeating: " --- |", count: width).joined()
        return shape.with([row(header), separatorRow] + rows.dropFirst().map(row))
    }

    /// Rows of fields: double-quoted fields may hold the delimiter, line
    /// breaks and doubled quotes. Text after a closing quote is kept as
    /// written. Blank lines are skipped. A quote that never closes is taken
    /// as an ordinary character, so it can't swallow the rest of the text.
    static func parseDelimited(_ text: String, delimiter: Character, quotes: Bool = true) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        // What follows a closing quote, before the next delimiter.
        var tail = ""
        var inQuotes = false
        var fieldWasQuoted = false
        var characters = text.makeIterator()
        var pending: Character? = nil

        func endField() {
            while let last = tail.last, last == " " || last == "\t" { tail.removeLast() }
            row.append(fieldWasQuoted ? field + tail : field.trimmingCharacters(in: .whitespaces))
            field = ""
            tail = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? characters.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    let next = characters.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
            } else if character == delimiter {
                endField()
            } else if character.isNewline {
                endRow()
            } else if quotes && character == "\"" && !fieldWasQuoted && field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                inQuotes = true
                fieldWasQuoted = true
            } else if fieldWasQuoted {
                tail.append(character)
            } else {
                field.append(character)
            }
        }
        if inQuotes { return parseDelimited(text, delimiter: delimiter, quotes: false) }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }

    // MARK: Helpers

    /// Sorts the non-blank lines; blank lines go to the end, so a sort
    /// never starts with a gap.
    private static func stableSort(_ text: String, by compare: (String, String) -> ComparisonResult) -> String {
        let lines = LineText(text)
        let sorted = lines.lines.enumerated().filter { !isBlank($0.element) }.sorted { a, b in
            switch compare(a.element, b.element) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.offset < b.offset
            }
        }
        return lines.with(sorted.map(\.element) + lines.lines.filter(isBlank))
    }

    private static func tableCell(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Whether `inner` (a quoted string without its outer quotes) has no
    /// quote of its own that would end it early: an unescaped `"`, or a `'`
    /// that isn't an apostrophe between two letters.
    private static func isOneString(_ inner: String, quote: Character) -> Bool {
        let characters = Array(inner)
        var escaped = false
        for (index, character) in characters.enumerated() {
            defer { escaped = quote == "\"" && character == "\\" && !escaped }
            guard character == quote, !escaped else { continue }
            if quote == "\"" { return false }
            let between = index > 0 && index + 1 < characters.count && characters[index - 1].isLetter && characters[index + 1].isLetter
            if !between { return false }
        }
        return true
    }

    /// Undoes `quote`'s escapes, `\"` and `\\`.
    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                // Only the two escapes Quote makes; "\n" and the like stay as written.
                if character != "\"" && character != "\\" { result.append("\\") }
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    private static func isBlank(_ line: String) -> Bool { TextTransforms.isBlank(line) }

    private static func leadingWhitespace(_ line: String) -> String { TextTransforms.leadingWhitespace(line) }
}
