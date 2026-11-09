import Foundation

/// A triage of PDFs for active content: SAFE, CHECK or NOT SAFE. It reads
/// qpdf's parsed objects (`qpdf --json`, no stream data), so only real
/// dictionary keys and name values count, never "/JS" bytes inside
/// compressed image data. It never changes the PDF.
enum CheckSafety {
    enum Verdict: Int, Comparable, Sendable {
        case safe, check, notSafe

        var label: String {
            switch self {
            case .safe: "SAFE"
            case .check: "CHECK"
            case .notSafe: "NOT SAFE"
            }
        }

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Result: Equatable, Sendable {
        let file: URL
        /// Each marker found, with how many times it appears.
        let markers: [String: Int]
        let verdict: Verdict
        let reason: String
    }

    static let dangerous: Set<String> = ["/JS", "/JavaScript", "/Launch", "/EmbeddedFile", "/EmbeddedFiles", "/RichMedia", "/XFA"]
    static let worthALook: Set<String> = ["/AcroForm", "/Encrypt", "/JBIG2Decode", "/ObjStm", "/OpenAction", "/AA"]
    static let caveat = "This is a triage, not an antivirus. SAFE means none of these markers were found, not that the file is harmless. Do not open a NOT SAFE file."

    /// `--warning-exit-0`: a damaged file qpdf can still read exits 0, and its
    /// warnings come on standard error.
    static func arguments(_ file: URL) -> [String] {
        ["--json=2", "--json-key=qpdf", "--json-key=encrypt", "--json-stream-data=none", "--warning-exit-0", file.path]
    }

    static func check(_ files: [URL], tools: ExternalTools = .current) async throws -> [Result] {
        var results: [Result] = []
        for file in files {
            results.append(try await check(file, tools: tools))
        }
        return results
    }

    static func check(_ file: URL, tools: ExternalTools = .current) async throws -> Result {
        guard let qpdf = tools.qpdf else { throw MissingToolError(name: "qpdf") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-checksafety-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        let errors = Lines()
        func shown(_ line: String) -> String { line.replacingOccurrences(of: file.path, with: file.lastPathComponent) }
        do {
            try await ProcessRunner.run(qpdf, arguments(file), standardOutputFile: output, onErrorLine: { errors.append($0) })
        } catch let failure as ProcessFailure {
            return unparsed(file, error: shown(failure.message))
        }
        guard let parsed = try? markers(inQPDFJSON: Data(contentsOf: output)) else {
            return unparsed(file, error: "qpdf's report was unreadable")
        }
        let warning = errors.all.first { $0.hasPrefix("WARNING") }.map(shown)
        let (verdict, reason) = verdict(markers: parsed, warning: warning)
        return Result(file: file, markers: parsed, verdict: verdict, reason: reason)
    }

    /// A file qpdf can't read is NOT SAFE when its raw bytes hold a dangerous
    /// name, since nothing can show it's only stream data; otherwise CHECK.
    static func unparsed(_ file: URL, error: String) -> Result {
        let raw = rawDangerousNames(in: (try? Data(contentsOf: file)) ?? Data())
        if raw.isEmpty {
            return Result(file: file, markers: [:], verdict: .check, reason: "could not parse the file: \(error)")
        }
        let names = raw.keys.sorted().joined(separator: " ")
        return Result(file: file, markers: raw, verdict: .notSafe, reason: "qpdf could not parse; raw bytes contain \(names) (\(error))")
    }

    /// Counts the dangerous names as whole PDF name tokens: "/JS" counts, "/JSON" doesn't.
    static func rawDangerousNames(in data: Data) -> [String: Int] {
        let text = String(decoding: data, as: Unicode.ASCII.self)
        let pattern = #"/(JS|JavaScript|Launch|EmbeddedFiles?|RichMedia|XFA)(?![^\s()<>\[\]{}/%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var counts: [String: Int] = [:]
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) { counts[String(text[range]), default: 0] += 1 }
        }
        return counts
    }

    /// Counts the markers among every dictionary key and name value in the
    /// objects and trailer. An encrypted file counts /Encrypt at least once.
    static func markers(inQPDFJSON data: Data) throws -> [String: Int] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let parts = json?["qpdf"] as? [Any], parts.count > 1, let objects = parts[1] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let wanted = dangerous.union(worthALook)
        var counts: [String: Int] = [:]
        func count(_ name: String) {
            if wanted.contains(name) { counts[name, default: 0] += 1 }
        }
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                dictionary.keys.forEach(count)
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            } else if let string = value as? String {
                count(string)
            }
        }
        for case let object as [String: Any] in objects.values {
            walk((object["stream"] as? [String: Any])?["dict"] ?? object["value"] ?? [:])
        }
        if ((json?["encrypt"] as? [String: Any])?["encrypted"] as? Bool) == true {
            counts["/Encrypt"] = max(counts["/Encrypt"] ?? 0, 1)
        }
        return counts
    }

    static func verdict(markers: [String: Int], warning: String?) -> (Verdict, String) {
        let found = Set(markers.keys)
        let bad = found.intersection(dangerous)
        let warn = found.intersection(worthALook)
        let opens = found.intersection(["/OpenAction", "/AA"])
        func listed(_ names: Set<String>) -> String { names.sorted().joined(separator: " ") }

        if !bad.isEmpty {
            return (.notSafe, "real \(listed(bad))" + (opens.isEmpty ? "" : ", runs on open via \(listed(opens))"))
        }
        if !warn.isEmpty || warning != nil {
            let reasons = (warn.isEmpty ? [] : ["real \(listed(warn)) (usually fine, worth a look)"])
                + (warning.map { ["qpdf warning: \($0)"] } ?? [])
            return (.check, reasons.joined(separator: "; "))
        }
        return (.safe, "no active content")
    }

    /// One report for every file, the worst verdict on top.
    static func report(_ results: [Result]) -> String {
        let ordered = results.enumerated()
            .sorted { $0.element.verdict != $1.element.verdict ? $0.element.verdict > $1.element.verdict : $0.offset < $1.offset }
            .map(\.element)
        let sections = ordered.map { result in
            let lines = result.markers.isEmpty
                ? ["  no markers"]
                : result.markers.keys.sorted().map { "  \($0)  \(result.markers[$0] ?? 0)" }
            return ([result.file.lastPathComponent] + lines + ["\(result.verdict.label): \(result.reason)"]).joined(separator: "\n")
        }
        return (sections + [caveat]).joined(separator: "\n\n")
    }

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }
}
