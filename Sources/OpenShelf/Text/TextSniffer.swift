import Foundation

/// The structured-data formats the text wheel's Convert sub-wheel moves between.
enum DataTextFormat: String, CaseIterable, Sendable {
    case json, yaml, edn, xml, toml

    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

/// Guesses what selected text is from its content alone, so Re-indent can
/// pick a formatter and Convert can name the source format.
enum TextSniffer {
    /// A file extension `PrettyPrint` knows for this text, or nil.
    static func codeExtension(for text: String) -> String? {
        if let data = dataFormat(of: text) {
            return data == .edn ? "edn" : data.fileExtension
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") { return "html" }
        if trimmed.hasPrefix("(") { return "clj" }
        if trimmed.hasPrefix("#!"), let firstLine = lower.split(separator: "\n").first,
           ["sh", "bash", "zsh"].contains(where: { firstLine.hasSuffix("/\($0)") || firstLine.hasSuffix(" \($0)") }) {
            return "sh"
        }
        let firstWord = lower.prefix { !$0.isWhitespace && $0 != "(" }
        if ["select", "insert", "update", "delete", "with", "create", "alter", "drop"].contains(String(firstWord)) { return "sql" }
        let lines = trimmed.components(separatedBy: "\n")
        if lines.contains(where: { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            return (line.hasPrefix("def ") || line.hasPrefix("class ")) && line.hasSuffix(":")
        }) { return "py" }
        if lines.contains(where: { $0.hasPrefix("import SwiftUI") || $0.hasPrefix("import Foundation") || $0.contains("func ") && $0.contains("->") }) {
            return "swift"
        }
        return nil
    }

    /// The structured-data format `text` parses as, or nil. Order matters:
    /// JSON is also valid YAML, and a lone word is valid YAML too.
    static func dataFormat(of text: String) -> DataTextFormat? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil,
           trimmed.first == "{" || trimmed.first == "[" {
            return .json
        }
        if trimmed.hasPrefix("<"), !trimmed.lowercased().hasPrefix("<!doctype html"), !trimmed.lowercased().hasPrefix("<html"),
           (try? XMLDocument(xmlString: trimmed, options: [])) != nil {
            return .xml
        }
        if looksLikeEDN(trimmed) { return .edn }
        if looksLikeTOML(trimmed) { return .toml }
        if looksLikeYAML(trimmed) { return .yaml }
        return nil
    }

    /// `{:key …}` or `[:key …]`, or a map or vector holding keywords: JSON
    /// would have failed above, and keywords are EDN's tell.
    static func looksLikeEDN(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" || first == "#" else { return false }
        return text.range(of: #"(^|[\s\[{(,]):[A-Za-z*+!_?<>=-]"#, options: .regularExpression) != nil
    }

    /// A `[table]` header or `key = value` lines, and no `key: value` lines.
    static func looksLikeTOML(_ text: String) -> Bool {
        let lines = significantLines(text)
        guard !lines.isEmpty else { return false }
        let assignments = lines.filter { $0.range(of: #"^[A-Za-z0-9_."'-]+\s*=\s*\S"#, options: .regularExpression) != nil }
        let tables = lines.filter { $0.range(of: #"^\[{1,2}[A-Za-z0-9_."' -]+\]{1,2}$"#, options: .regularExpression) != nil }
        return !assignments.isEmpty && assignments.count + tables.count == lines.count
    }

    /// Every significant line is `key: value`, `key:`, or a `- item`, at least one a key.
    static func looksLikeYAML(_ text: String) -> Bool {
        let lines = significantLines(text).filter { $0 != "---" }
        guard !lines.isEmpty else { return false }
        let keyed = lines.filter { $0.range(of: #"^(- )?[A-Za-z0-9_"'-][^:]*:(\s|$)"#, options: .regularExpression) != nil }
        let listed = lines.filter { $0.hasPrefix("- ") }
        return !keyed.isEmpty && Set(keyed + listed).count == Set(lines).count
    }

    private static func significantLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
