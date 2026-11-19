import Foundation

/// The Extract ▸ tools: what of one kind the text holds, one per line, in
/// the order found, each once. Nothing found leaves the text as it is.
enum ExtractTransforms {
    enum Kind: CaseIterable {
        case links, emails, numbers, phoneNumbers, dates
    }

    static func extract(_ kind: Kind, from text: String) -> String {
        let found = matches(kind, in: text)
        var seen = Set<String>()
        // Numbers keep repeats: a column of amounts can hold the same one twice.
        let unique = kind == .numbers ? found : found.filter { seen.insert($0).inserted }
        return unique.isEmpty ? text : unique.joined(separator: "\n")
    }

    static func matches(_ kind: Kind, in text: String) -> [String] {
        let whole = NSRange(text.startIndex..., in: text)
        func strings(_ results: [NSTextCheckingResult]) -> [String] {
            results.compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        switch kind {
        case .links:
            let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            return detector.matches(in: text, range: whole).filter { $0.url?.scheme?.lowercased() != "mailto" }.compactMap { result in
                guard let range = Range(result.range, in: text) else { return nil }
                return String(text[range])
            }
        case .emails:
            let pattern = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
            return strings(pattern.matches(in: text, range: whole))
        case .numbers:
            // Signed, with thousands separators and a decimal part. Not digits
            // inside words ("v2"), or parts of an IP, a version, a date or a time.
            let pattern = try! NSRegularExpression(pattern: #"(?<![\w.\-/:])[-+]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?!\w|[.\-/:]\d)"#)
            return strings(pattern.matches(in: text, range: whole))
        case .phoneNumbers:
            let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
            return strings(detector.matches(in: text, range: whole))
        case .dates:
            let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            return strings(detector.matches(in: text, range: whole))
        }
    }
}
