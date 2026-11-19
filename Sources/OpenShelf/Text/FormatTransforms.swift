import Foundation

/// The Format ▸ tools beyond Indent: wrap the text in something, tidy
/// Markdown, and convert a date between Unix time, ISO 8601 and words.
enum FormatTransforms {
    enum Wrapper: CaseIterable {
        case quotes, parentheses, brackets, braces, codeFence, blockQuote
    }

    /// The text inside the wrapper; a final line break stays outside it.
    static func wrap(_ text: String, in wrapper: Wrapper) -> String {
        let ending = text.hasSuffix("\n") ? "\n" : ""
        let body = ending.isEmpty ? text : String(text.dropLast())
        switch wrapper {
        case .quotes: return "\"\(body)\"" + ending
        case .parentheses: return "(\(body))" + ending
        case .brackets: return "[\(body)]" + ending
        case .braces: return "{\(body)}" + ending
        case .codeFence: return "```\n\(body)\n```" + ending
        case .blockQuote:
            return body.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n") + ending
        }
    }

    /// "[text](url)" when `link` is a web or mail address, else nil.
    static func markdownLink(_ text: String, link: String?) -> String? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.contains(where: \.isWhitespace),
              let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return nil }
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "]", with: "\\]")
        return "[\(label)](\(link))"
    }

    /// A Markdown table's columns padded to line up, alignment colons kept.
    /// Lines that aren't table rows are left as they are.
    static func alignTable(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        func cells(_ line: String) -> [String]? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { return nil }
            var inner = trimmed.dropFirst()
            if inner.hasSuffix("|") { inner = inner.dropLast() }
            return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let rows = lines.map(cells)
        func isSeparator(_ row: [String]) -> Bool { !row.isEmpty && row.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } } }
        let columns = rows.compactMap { $0?.count }.max() ?? 0
        guard columns > 0 else { return text }
        var widths = Array(repeating: 3, count: columns)
        for row in rows.compactMap({ $0 }) where !isSeparator(row) {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        return zip(lines, rows).map { line, row -> String in
            guard let row else { return line }
            let padded = (0..<columns).map { i -> String in
                let cell = i < row.count ? row[i] : ""
                if isSeparator(row) {
                    let left = cell.hasPrefix(":"), right = cell.hasSuffix(":") && cell.count > 1
                    return (left ? ":" : "-") + String(repeating: "-", count: widths[i] - 2) + (right ? ":" : "-")
                }
                return cell + String(repeating: " ", count: widths[i] - cell.count)
            }
            return "| " + padded.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
    }

    /// Headings one level bigger (fewer #) or smaller (more #), from # to ######.
    static func heading(_ text: String, up: Bool) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            let hashes = line.prefix { $0 == "#" }.count
            guard hashes > 0, hashes <= 6, line.dropFirst(hashes).first == " " else { return line }
            let level = up ? max(hashes - 1, 1) : min(hashes + 1, 6)
            return String(repeating: "#", count: level) + line.dropFirst(hashes)
        }.joined(separator: "\n")
    }

    /// A Unix time (seconds or milliseconds) becomes ISO 8601 with the local
    /// offset; ISO 8601 becomes Unix seconds; a date in words becomes ISO
    /// 8601. Anything else is left as it is.
    static func convertDate(_ text: String, timeZone: TimeZone = .current) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        if trimmed.count >= 9, trimmed.count <= 13, trimmed.allSatisfy(\.isASCII), let value = Double(trimmed), trimmed.allSatisfy(\.isNumber) {
            let seconds = trimmed.count >= 12 ? value / 1000 : value
            return iso.string(from: Date(timeIntervalSince1970: seconds))
        }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) ?? isoWithFraction.date(from: trimmed) {
            return String(Int(date.timeIntervalSince1970))
        }
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = detector.firstMatch(in: trimmed, range: whole), match.range == whole, let date = match.date {
            return iso.string(from: date)
        }
        return text
    }
}
