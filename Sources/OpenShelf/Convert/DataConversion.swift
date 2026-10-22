import Foundation

/// Data files: JSON and property lists with Foundation; YAML, XML and CSV
/// with yq (mikefarah/yq, Homebrew's `yq`), which reads and writes them all.
enum DataConversion {
    static let dataFormats: Set<OutputFormat> = [.json, .yaml, .xml, .plist, .csv]

    /// What a data file (or CSV/TSV table) with `pathExtension` can become.
    static func formats(forExtension pathExtension: String, tools: ExternalTools) -> [OutputFormat] {
        let hasYQ = tools.yq != nil
        switch pathExtension.lowercased() {
        case "json": return hasYQ ? [.yaml, .xml, .plist, .csv] : [.plist]
        case "yaml", "yml": return hasYQ ? [.json, .xml, .plist, .csv] : []
        case "xml": return hasYQ ? [.json, .yaml] : []
        case "plist": return hasYQ ? [.json, .yaml] : [.json]
        case "csv", "tsv": return hasYQ ? [.json, .yaml, .xml] : []
        default: return []
        }
    }

    static func convert(_ source: URL, to format: OutputFormat, tools: ExternalTools) async throws -> URL {
        let input = source.pathExtension.lowercased()
        guard formats(forExtension: input, tools: tools).contains(format), let pathExtension = format.fileExtension else {
            if tools.yq == nil, input != "json", input != "plist" { throw MissingToolError(name: "yq") }
            throw ConversionError.unsupported("\(input.uppercased()) to \(format.title)")
        }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        try await PartialFile.write(destination) { partial in
            switch (input, format) {
            case ("json", .plist):
                try plist(fromJSON: Data(contentsOf: source)).write(to: partial)
            case ("plist", .json):
                try json(fromPlist: Data(contentsOf: source)).write(to: partial)
            case (_, .plist):
                // YAML to JSON with yq, then to a property list.
                let json = try await yq(tools, from: input, to: "json", source: source)
                try plist(fromJSON: json).write(to: partial)
            case ("plist", _):
                let json = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: json) }
                try self.json(fromPlist: Data(contentsOf: source)).write(to: json)
                try await yq(tools, from: "json", to: format, source: json, output: partial)
            default:
                try await yq(tools, from: input, to: format, source: source, output: partial)
            }
        }
        return destination
    }

    // MARK: yq

    /// yq's name for the format of a file with `pathExtension`.
    static func yqFormat(_ pathExtension: String) -> String {
        switch pathExtension {
        case "yml": "yaml"
        default: pathExtension
        }
    }

    /// yq's expression and flags for writing `format`. XML needs a single
    /// root element, so anything else is wrapped in <root>, a list's
    /// entries as <item>s.
    static func yqArguments(from input: String, to format: OutputFormat, source: URL) -> [String] {
        let output = yqFormat(format.rawValue)
        let expression = format == .xml && input != "xml"
            ? #"if (tag == "!!map" and length == 1) then . elif tag == "!!seq" then {"root": {"item": .}} else {"root": .} end"#
            : "."
        return ["--input-format", yqFormat(input), "--output-format", output, expression, source.path]
    }

    private static func yq(_ tools: ExternalTools, from input: String, to format: OutputFormat, source: URL, output: URL) async throws {
        guard let yq = tools.yq else { throw MissingToolError(name: "yq") }
        try await ProcessRunner.run(yq, yqArguments(from: input, to: format, source: source), standardOutputFile: output)
    }

    private static func yq(_ tools: ExternalTools, from input: String, to output: String, source: URL) async throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).\(output)")
        defer { try? FileManager.default.removeItem(at: file) }
        try await yq(tools, from: input, to: .json, source: source, output: file)
        return try Data(contentsOf: file)
    }

    // MARK: Foundation

    /// An XML property list of the JSON in `data`. Property lists have no null.
    static func plist(fromJSON data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard PropertyListSerialization.propertyList(object, isValidFor: .xml), !containsNull(object) else {
            throw ConversionError.failed("This JSON has null values, which a property list can’t hold.")
        }
        return try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    /// Pretty-printed JSON of a property list (XML or binary). Dates become
    /// ISO 8601 strings and data base64, since JSON has neither.
    static func json(fromPlist data: Data) throws -> Data {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try JSONSerialization.data(withJSONObject: jsonCompatible(object), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    private static func jsonCompatible(_ value: Any) -> Any {
        switch value {
        case let date as Date: ISO8601DateFormatter().string(from: date)
        case let data as Data: data.base64EncodedString()
        case let array as [Any]: array.map(jsonCompatible)
        case let dictionary as [String: Any]: dictionary.mapValues(jsonCompatible)
        default: value
        }
    }

    private static func containsNull(_ value: Any) -> Bool {
        switch value {
        case is NSNull: true
        case let array as [Any]: array.contains(where: containsNull)
        case let dictionary as [String: Any]: dictionary.values.contains(where: containsNull)
        default: false
        }
    }
}
