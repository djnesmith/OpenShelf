import Foundation

/// The Code ▸ tools: encode and decode, read a JWT, generate. Pure Swift.
/// A decode that can't read the text returns it unchanged, which the wheel
/// reports as "Nothing to change".
enum CodeTransforms {
    enum Format: CaseIterable {
        case url, base64, html, jsonString, hex, unicode
    }

    static func encode(_ text: String, as format: Format) -> String {
        switch format {
        case .url:
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
        case .base64:
            return Data(text.utf8).base64EncodedString()
        case .html:
            return text.map { c -> String in
                switch c {
                case "&": "&amp;"
                case "<": "&lt;"
                case ">": "&gt;"
                case "\"": "&quot;"
                case "'": "&#39;"
                default: String(c)
                }
            }.joined()
        case .jsonString:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return (try? encoder.encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? text
        case .hex:
            return text.utf8.map { String(format: "%02x", $0) }.joined()
        case .unicode:
            return text.unicodeScalars.map { scalar -> String in
                if scalar.isASCII { return String(scalar) }
                return String(scalar.utf16.map { String(format: "\\u%04x", $0) }.joined())
            }.joined()
        }
    }

    static func decode(_ text: String, from format: Format) -> String {
        switch format {
        case .url:
            return text.removingPercentEncoding ?? text
        case .base64:
            return base64Data(text).flatMap { String(data: $0, encoding: .utf8) } ?? text
        case .html:
            return FixTransforms.decodeEntities(text)
        case .jsonString:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let quoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 ? trimmed : "\"" + trimmed + "\""
            return (try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))) ?? text
        case .hex:
            var digits = text.replacingOccurrences(of: "0x", with: "").filter { !$0.isWhitespace && $0 != ":" && $0 != "," }
            guard digits.count % 2 == 0, digits.allSatisfy(\.isHexDigit) else { return text }
            var bytes: [UInt8] = []
            while !digits.isEmpty {
                bytes.append(UInt8(digits.prefix(2), radix: 16)!)
                digits.removeFirst(2)
            }
            return String(bytes: bytes, encoding: .utf8) ?? text
        case .unicode:
            return decodeUnicodeEscapes(text)
        }
    }

    /// Base64, also the URL-safe kind, with or without padding and line breaks.
    static func base64Data(_ text: String) -> Data? {
        var clean = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while clean.count % 4 != 0 { clean += "=" }
        return Data(base64Encoded: clean)
    }

    /// \uXXXX (surrogate pairs joined), \UXXXXXXXX and \u{…}.
    static func decodeUnicodeEscapes(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"\\u\{([0-9a-fA-F]{1,6})\}|\\U([0-9a-fA-F]{8})|((?:\\u[0-9a-fA-F]{4})+)"#)
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            var replacement: String?
            if let braced = Range(match.range(at: 1), in: result) ?? Range(match.range(at: 2), in: result) {
                replacement = UInt32(result[braced], radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if let run = Range(match.range(at: 3), in: result) {
                let units = result[run].split(separator: "\\").compactMap { UInt16($0.dropFirst(), radix: 16) }
                replacement = String(utf16CodeUnits: units, count: units.count)
            }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    // MARK: - JWT

    /// A JWT's header and payload as indented JSON, a blank line between.
    /// The signature is not checked. Nil when the text isn't a JWT.
    static func readJWT(_ text: String) -> String? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 5 else { return nil }
        let decoded = parts.prefix(2).compactMap { part -> String? in
            guard let data = base64Data(String(part)), let object = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
            return String(data: pretty, encoding: .utf8)
        }
        return decoded.count == 2 ? decoded.joined(separator: "\n\n") : nil
    }

    // MARK: - Generate

    static func uuid() -> String { UUID().uuidString }

    /// Now, as ISO 8601 with the local offset ("2026-11-19T10:15:00-05:00").
    static func timestamp(now: Date = .now, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now)
    }

    static let loremIpsum = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

    /// 20 characters from letters, digits and symbols, from the system's
    /// secure random source; at least one of each kind.
    static func password(length: Int = 20) -> String {
        let lower = Array("abcdefghijkmnopqrstuvwxyz"), upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("23456789"), symbols = Array("!#$%&*+-=?@^_~")
        let all = lower + upper + digits + symbols
        var generator = SystemRandomNumberGenerator()
        var chars = [lower, upper, digits, symbols].map { $0.randomElement(using: &generator)! }
        while chars.count < length { chars.append(all.randomElement(using: &generator)!) }
        return String(chars.shuffled(using: &generator))
    }
}
