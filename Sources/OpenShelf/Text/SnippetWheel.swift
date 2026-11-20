import AppKit
import Carbon.HIToolbox

/// The Snippets wheel's wedges (ROADMAP C8): the folder's own snippets and groups first,
/// then the built-in dates and times behind "Dates & Times ▸"; with an empty folder, the
/// built-ins are the wheel.
enum SnippetWheel {
    /// The built-ins' group, a path no folder can have.
    static let datesPath = "\u{1}Dates & Times"

    static let folderKey = "SnippetsFolder"
    /// Not decided by David: the Snippets wheel's own hotkey. ⌃⌥I ("insert").
    static let shortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: [.control, .option], keyName: "I")

    /// Where the snippet files are: the folder chosen in Settings, or Application Support.
    static func folder(_ defaults: UserDefaults = .standard) -> URL {
        if let path = defaults.string(forKey: folderKey) { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenShelf/Snippets", isDirectory: true)
    }

    static var builtIns: [Snippets.Entry] { Snippets.BuiltIn.allCases.map { Snippets.Entry(name: $0.name, source: .builtIn($0)) } }

    /// The commands for the group at `path` of `library`.
    static func commands(for library: Snippets.Group, at path: String) -> [TextCommand] {
        let ownEmpty = library.entries.isEmpty && library.groups.isEmpty
        if path == datesPath {
            return builtIns.map(TextCommand.snippet) + (ownEmpty ? [] : [.snippetBack("")])
        }
        if path.isEmpty, ownEmpty { return builtIns.map(TextCommand.snippet) }
        guard let group = library.group(at: path) else { return [] }
        var commands = group.entries.map(TextCommand.snippet) + group.groups.map { TextCommand.snippetGroup($0.path) }
        if path.isEmpty {
            commands.append(.snippetGroup(datesPath))
        } else {
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            commands.append(.snippetBack(parent))
        }
        return commands
    }

    /// A snippet's text with its placeholders filled in.
    static func expand(_ entry: Snippets.Entry, context: Snippets.Context, defaults: UserDefaults = .standard) -> Result<Snippets.Expanded, Snippets.Problem> {
        switch entry.source {
        case .builtIn(let builtIn):
            let format = defaults.string(forKey: "SnippetFormat.\(builtIn.rawValue)")
            return .success(Snippets.Expanded(text: builtIn.text(at: context.now, calendar: context.calendar, format: format), charactersAfterCursor: 0))
        case .file(let url):
            guard let body = try? String(contentsOf: url, encoding: .utf8) else {
                return .failure(Snippets.Problem(file: url.lastPathComponent, line: 1, message: "couldn't read the file as UTF-8 text"))
            }
            // A file's own final line break isn't part of the snippet.
            let trimmed = body.hasSuffix("\n") ? String(body.dropLast()) : body
            return Snippets.expand(trimmed, file: url.lastPathComponent, context: context)
        }
    }

    /// Presses ← `count` times, to put the cursor where `{cursor}` was.
    static func pressLeft(_ count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<min(count, 10_000) {
            for isDown in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: isDown)?.post(tap: .cgSessionEventTap)
            }
        }
    }
}

extension Snippets.Entry {
    var systemImage: String {
        switch source {
        case .builtIn(.time), .builtIn(.isoTimestamp), .builtIn(.unixTime): "clock"
        case .builtIn: "calendar"
        case .file: "text.quote"
        }
    }
}
