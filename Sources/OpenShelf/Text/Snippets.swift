import Foundation

/// Snippets (ROADMAP C8): built-in dates and times, and a folder of small plain-text
/// files, one snippet a file (its name the snippet's), subfolders as groups. A file may
/// hold placeholders and one `{cursor}`. Pure: expansion takes its clock, clipboard and
/// selection as input.
enum Snippets {
    enum BuiltIn: String, CaseIterable, Hashable, Sendable {
        case isoDate, longDate, time, isoTimestamp, unixTime, isoWeek

        var name: String {
            switch self {
            case .isoDate: "ISO Date"
            case .longDate: "Long Date"
            case .time: "Time"
            case .isoTimestamp: "ISO Timestamp"
            case .unixTime: "Unix Time"
            case .isoWeek: "ISO Week"
            }
        }

        /// The date pattern; `UserDefaults` key "SnippetFormat.<rawValue>" replaces it.
        var defaultFormat: String {
            switch self {
            case .isoDate: "yyyy-MM-dd"
            case .longDate: "MMMM d, yyyy"
            case .time: "HH:mm"
            case .isoTimestamp: "yyyy-MM-dd'T'HH:mm:ssXXXXX"
            case .unixTime: ""
            case .isoWeek: "YYYY-'W'ww"
            }
        }

        func text(at now: Date, calendar: Calendar, format: String? = nil) -> String {
            if self == .unixTime { return String(Int(now.timeIntervalSince1970)) }
            // ISO weeks start on Monday and need four days in the year.
            var used = calendar
            if self == .isoWeek {
                used = Calendar(identifier: .iso8601)
                used.timeZone = calendar.timeZone
            }
            return Snippets.format(now, format ?? defaultFormat, calendar: used)
        }
    }

    enum Source: Hashable, Sendable {
        case builtIn(BuiltIn)
        case file(URL)
    }

    struct Entry: Hashable, Sendable {
        var name: String
        var source: Source
    }

    /// A folder of snippets: its own entries, then its subfolders.
    struct Group: Equatable, Sendable {
        var name: String
        var path: String
        var entries: [Entry]
        var groups: [Group]

        /// The group at `path` ("Work/Replies") under this one, or nil.
        func group(at path: String) -> Group? {
            if path == self.path { return self }
            for group in groups { if let found = group.group(at: path) { return found } }
            return nil
        }
    }

    static let fileExtensions: Set<String> = ["txt", "text", "md", ""]

    /// The folder as a tree of groups. Hidden files and other kinds of file are skipped.
    static func load(folder: URL, path: String = "") -> Group {
        let manager = FileManager.default
        let items = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var entries: [Entry] = []
        var groups: [Group] = []
        for item in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let child = path.isEmpty ? item.lastPathComponent : "\(path)/\(item.lastPathComponent)"
                groups.append(load(folder: item, path: child))
            } else if fileExtensions.contains(item.pathExtension.lowercased()) {
                entries.append(Entry(name: item.deletingPathExtension().lastPathComponent, source: .file(item)))
            }
        }
        return Group(name: path.isEmpty ? "Snippets" : folder.lastPathComponent, path: path, entries: entries, groups: groups)
    }

    struct Context {
        var now: Date
        var calendar: Calendar
        var clipboard: String?
        var selection: String
        var uuid: () -> String = { UUID().uuidString }
    }

    /// The text to put in, and how many characters of it come after `{cursor}` (how many
    /// times to press ←).
    struct Expanded: Equatable {
        var text: String
        var charactersAfterCursor: Int
    }

    struct Problem: Error, Equatable {
        var file: String
        var line: Int
        var message: String

        var description: String { "\(file), line \(line): \(message)" }
    }

    /// Fills in the placeholders of `body`. `{{` and `}}` are literal braces.
    static func expand(_ body: String, file: String, context: Context) -> Result<Expanded, Problem> {
        var out = ""
        var cursorAt: String.Index?
        var index = body.startIndex
        var line = 1
        while index < body.endIndex {
            let character = body[index]
            if body[index...].hasPrefix("{{") || body[index...].hasPrefix("}}") {
                out.append(character)
                index = body.index(index, offsetBy: 2)
                continue
            }
            guard character == "{" else {
                if character == "\n" { line += 1 }
                out.append(character)
                index = body.index(after: index)
                continue
            }
            guard let close = body[index...].firstIndex(of: "}") else {
                return .failure(Problem(file: file, line: line, message: "a { with no }"))
            }
            let inside = String(body[body.index(after: index)..<close])
            guard let (name, attributes) = parse(inside) else {
                return .failure(Problem(file: file, line: line, message: "can't read {\(inside)}"))
            }
            switch placeholder(name, attributes, context: context) {
            case .failure(let error):
                return .failure(Problem(file: file, line: line, message: error.message))
            case .success(nil):
                guard cursorAt == nil else { return .failure(Problem(file: file, line: line, message: "{cursor} more than once")) }
                cursorAt = out.endIndex
            case .success(let text?):
                out += text
            }
            index = body.index(after: close)
        }
        let after = cursorAt.map { out[$0...].count } ?? 0
        return .success(Expanded(text: out, charactersAfterCursor: after))
    }

    /// `date format="yyyy" offset="+3d"` as the name and its attributes.
    private static func parse(_ inside: String) -> (String, [String: String])? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*([a-z]+)((?:\s+[a-z]+="[^"]*")*)\s*$"#),
              let match = regex.firstMatch(in: inside, range: NSRange(inside.startIndex..., in: inside)),
              let nameRange = Range(match.range(at: 1), in: inside), let restRange = Range(match.range(at: 2), in: inside) else { return nil }
        var attributes: [String: String] = [:]
        let rest = String(inside[restRange])
        let pairs = try! NSRegularExpression(pattern: #"([a-z]+)="([^"]*)""#)
        for pair in pairs.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
            attributes[String(rest[Range(pair.range(at: 1), in: rest)!])] = String(rest[Range(pair.range(at: 2), in: rest)!])
        }
        return (String(inside[nameRange]), attributes)
    }

    /// A placeholder's text; nil for `{cursor}`; a message when it can't be filled.
    private static func placeholder(_ name: String, _ attributes: [String: String], context: Context) -> Result<String?, PlaceholderError> {
        let allowed: [String: Set<String>] = ["date": ["format", "offset"], "time": ["format", "offset"]]
        if let unknown = attributes.keys.first(where: { !(allowed[name] ?? []).contains($0) }) {
            return .failure(PlaceholderError("{\(name)} has no \(unknown)=\"…\""))
        }
        switch name {
        case "date", "time":
            var when = context.now
            if let offset = attributes["offset"] {
                guard let shifted = shift(when, by: offset, calendar: context.calendar) else {
                    return .failure(PlaceholderError("offset=\"\(offset)\" isn't like \"+3d\" or \"-1w\""))
                }
                when = shifted
            }
            return .success(format(when, attributes["format"] ?? (name == "date" ? "yyyy-MM-dd" : "HH:mm"), calendar: context.calendar))
        case "clipboard": return .success(context.clipboard ?? "")
        case "selection": return .success(context.selection)
        case "cursor": return .success(nil)
        case "uuid": return .success(context.uuid())
        case "epoch": return .success(String(Int(context.now.timeIntervalSince1970)))
        default: return .failure(PlaceholderError("no placeholder called {\(name)}"))
        }
    }

    struct PlaceholderError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    /// "+3d", "-1w", "+2m" (months), "+1y", "+4h".
    static func shift(_ date: Date, by offset: String, calendar: Calendar) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"^([+-]\d{1,4})([hdwmy])$"#),
              let match = regex.firstMatch(in: offset, range: NSRange(offset.startIndex..., in: offset)),
              let amount = Int(offset[Range(match.range(at: 1), in: offset)!]) else { return nil }
        let unit: Calendar.Component = switch offset[Range(match.range(at: 2), in: offset)!] {
        case "h": .hour
        case "d": .day
        case "w": .weekOfYear
        case "m": .month
        default: .year
        }
        return calendar.date(byAdding: unit, value: amount, to: date)
    }

    static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
