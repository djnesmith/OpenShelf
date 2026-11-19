import Foundation

/// The Fix ▸ tools: text pasted from the web, a terminal or a mis-read file
/// made plain again. Pure Swift; nothing is fetched or run.
enum FixTransforms {
    // MARK: - Plain Text

    /// HTML or Markdown as plain text, whichever the text is. HTML wins when
    /// it has tags; otherwise Markdown's marks are taken off.
    static func plainText(_ text: String) -> String {
        // Entities alone ("caf&#233;") are HTML-escaped text too.
        looksLikeHTML(text) ? htmlToText(text) : decodeEntities(markdownToText(text))
    }

    static func looksLikeHTML(_ text: String) -> Bool {
        text.range(of: #"</?[a-zA-Z][a-zA-Z0-9]*(\s[^<>]*)?/?>"#, options: .regularExpression) != nil
    }

    /// Tags go; block ends and <br> become line breaks; script and style go
    /// with their content; entities are decoded. Runs of blank lines become one.
    static func htmlToText(_ html: String) -> String {
        var text = html
        text = replace(text, #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, with: "")
        text = replace(text, #"(?is)<!--.*?-->"#, with: "")
        text = replace(text, #"(?i)<br\s*/?>"#, with: "\n")
        text = replace(text, #"(?i)<li\b[^>]*>"#, with: "\n• ")
        text = replace(text, #"(?i)</(p|div|h[1-6]|li|tr|blockquote|pre|ul|ol|table|section|article|header|footer)\s*>"#, with: "\n\n")
        text = replace(text, #"<[^>]+>"#, with: "")
        text = decodeEntities(text)
        text = replace(text, #"[ \t]+\n"#, with: "\n")
        text = replace(text, #"\n{3,}"#, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Headings, emphasis, inline code, links and images, quotes and fences
    /// lose their marks; the words stay. List bullets stay, as text.
    static func markdownToText(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").compactMap { line -> String? in
            var line = line
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { return nil }
            line = replace(line, #"^(\s*)#{1,6}\s+"#, with: "$1")
            line = replace(line, #"^(\s*)>\s?"#, with: "$1")
            line = replace(line, #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1")
            line = replace(line, #"\[([^\]]+)\]\([^)]*\)"#, with: "$1")
            line = replace(line, #"`([^`]*)`"#, with: "$1")
            line = replace(line, #"(\*\*|__)(\S(?:.*?\S)?)\1"#, with: "$2")
            line = replace(line, #"(?<![\w*])\*(\S(?:[^*]*?\S)?)\*(?![\w*])"#, with: "$1")
            line = replace(line, #"(?<![\w_])_(\S(?:[^_]*?\S)?)_(?![\w_])"#, with: "$1")
            line = replace(line, #"~~(\S(?:.*?\S)?)~~"#, with: "$1")
            return line
        }.joined(separator: "\n")
    }

    static func decodeEntities(_ text: String) -> String {
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"]
        var result = text
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        // Numeric entities, decimal and hex.
        let pattern = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result), let body = Range(match.range(at: 1), in: result) else { continue }
            let digits = result[body]
            let value = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let value, let scalar = Unicode.Scalar(value) { result.replaceSubrange(range, with: String(Character(scalar))) }
        }
        // &amp; last, so "&amp;lt;" stays "&lt;".
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Strip Tracking

    /// Query parameters that only track the click.
    static let trackingParameters: Set<String> = ["fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_eid", "mc_cid", "igshid", "yclid", "_hsenc", "_hsmi", "mkt_tok"]

    static func isTracking(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    /// Every web link in the text loses its tracking parameters; other
    /// parameters, the fragment and the rest of the text stay as they are.
    static func stripTracking(_ text: String) -> String {
        let links = try! NSRegularExpression(pattern: #"https?://[^\s<>"')\]]+"#, options: .caseInsensitive)
        var result = text
        for match in links.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: cleanLink(String(result[range])))
        }
        return result
    }

    static func cleanLink(_ link: String) -> String {
        guard let query = link.firstIndex(of: "?") else { return link }
        let base = link[..<query]
        let afterQuery = link[link.index(after: query)...]
        let fragmentStart = afterQuery.firstIndex(of: "#")
        let queryText = fragmentStart.map { afterQuery[..<$0] } ?? afterQuery
        let fragment = fragmentStart.map { String(afterQuery[$0...]) } ?? ""
        let kept = queryText.split(separator: "&", omittingEmptySubsequences: true).filter { pair in
            !isTracking(String(pair.split(separator: "=", maxSplits: 1).first ?? ""))
        }
        return String(base) + (kept.isEmpty ? "" : "?" + kept.joined(separator: "&")) + fragment
    }

    // MARK: - Fix Encoding

    /// Text written as UTF-8 and read as Windows-1252 ("cafÃ©", "itâ€™s")
    /// read again as UTF-8. Text that isn't mis-read comes back unchanged.
    static func fixEncoding(_ text: String) -> String {
        guard text.contains(where: { "ÃÂâÅÆÐÑ".contains($0) }) else { return text }
        // Each character back to the byte it was read from: Windows-1252, or
        // Latin-1 for the five bytes Windows-1252 leaves undefined (0x81, 0x8D,
        // 0x8F, 0x90, 0x9D; "”" read this way ends in U+009D).
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            if let byte = windows1252[scalar] {
                bytes.append(byte)
            } else if scalar.value < 0x100 {
                bytes.append(UInt8(scalar.value))
            } else {
                return text
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? text
    }

    /// Windows-1252's characters for 0x80-0x9F, by character.
    private static let windows1252: [Unicode.Scalar: UInt8] = {
        let high: [UInt32] = [0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
                              0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178]
        var table: [Unicode.Scalar: UInt8] = [:]
        for (offset, value) in high.enumerated() where value != 0 { table[Unicode.Scalar(value)!] = UInt8(0x80 + offset) }
        return table
    }()

    // MARK: - Strip ANSI

    /// Terminal colour and cursor codes (CSI "\e[…m", OSC "\e]…\a") go; the text stays.
    static func stripANSI(_ text: String) -> String {
        var result = replace(text, "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", with: "")
        result = replace(result, "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "")
        return replace(result, "\u{1B}[@-Z\\\\-_]", with: "")
    }

    private static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
