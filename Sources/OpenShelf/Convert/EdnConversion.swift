import Foundation

/// EDN (Clojure's data notation) to and from JSON and YAML, with jet.
///
/// EDN holds more than JSON: keywords and symbols become strings, sets
/// become arrays, #inst and #uuid their text, and other keys their printed
/// form. A tagged literal jet can't render (#my/tag …) is refused rather
/// than guessed at. JSON and YAML keys become keywords only where they're
/// valid ones, so "weird key" stays a string.
enum EdnConversion {
    /// jet's --keywordize function: keywords only for keys EDN can read back as one.
    static let keywordizeValidKeys = #"(fn [k] (if (re-matches #"[A-Za-z*+!_?<>=-][A-Za-z0-9*+!_?<>=.-]*" k) (keyword k) k))"#

    /// What a JSON, YAML or EDN file gains with jet (and yq, for EDN → YAML).
    static func formats(forExtension pathExtension: String, tools: ExternalTools) -> [OutputFormat] {
        guard tools.jet != nil else { return [] }
        switch pathExtension.lowercased() {
        case "edn": return [.json] + (tools.yq != nil ? [.yaml] : [])
        case "json", "yaml", "yml": return [.edn]
        default: return []
        }
    }

    static func handles(_ source: URL, to format: OutputFormat) -> Bool {
        format == .edn || source.pathExtension.lowercased() == "edn"
    }

    static func arguments(from input: String, to output: String) -> [String] {
        var arguments = ["--from", input, "--to", output]
        if output == "edn" { arguments += ["--keywordize", keywordizeValidKeys] }
        return arguments
    }

    static func convert(_ source: URL, to format: OutputFormat, tools: ExternalTools) async throws -> URL {
        guard let jet = tools.jet else { throw MissingToolError(name: "jet") }
        let input = source.pathExtension.lowercased() == "yml" ? "yaml" : source.pathExtension.lowercased()
        guard formats(forExtension: input, tools: tools).contains(format), let pathExtension = format.fileExtension else {
            throw ConversionError.unsupported("\(input.uppercased()) to \(format.title)")
        }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        try await PartialFile.write(destination) { partial in
            do {
                if input == "edn", format == .yaml {
                    // jet's own YAML loses symbols, so through JSON and yq.
                    guard let yq = tools.yq else { throw MissingToolError(name: "yq") }
                    let json = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).json")
                    defer { try? FileManager.default.removeItem(at: json) }
                    try await ProcessRunner.run(jet, arguments(from: "edn", to: "json"), standardInputFile: source, standardOutputFile: json)
                    try await ProcessRunner.run(yq, ["--input-format", "json", "--output-format", "yaml", ".", json.path], standardOutputFile: partial)
                } else {
                    try await ProcessRunner.run(jet, arguments(from: input, to: format == .edn ? "edn" : format.rawValue), standardInputFile: source, standardOutputFile: partial)
                }
            } catch let failure as ProcessFailure {
                throw explain(failure, source: source)
            }
        }
        return destination
    }

    /// jet's Java stack trace, as something a person can act on.
    static func explain(_ failure: ProcessFailure, source: URL) -> Error {
        let message = failure.errorOutput
        if message.contains("TaggedLiteral") {
            return ConversionError.failed("“\(source.lastPathComponent)” has a tagged value (like #my/tag) that JSON can’t hold, so nothing was saved.")
        }
        if message.contains("EOF") || message.contains("Unexpected") || message.contains("Invalid") || message.contains("Unmatched") {
            return ConversionError.failed("“\(source.lastPathComponent)” isn’t valid \(source.pathExtension.uppercased()).")
        }
        return failure
    }
}
