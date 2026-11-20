import Foundation
import Testing
@testable import OpenShelf

/// Snippets (ROADMAP C8), with a fixed clock and time zone.
struct SnippetsTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-12-30 14:22:05 in New York.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 14, minute: 22, second: 5))!

    static func context(clipboard: String? = "CLIP", selection: String = "SEL") -> Snippets.Context {
        Snippets.Context(now: now, calendar: calendar, clipboard: clipboard, selection: selection, uuid: { "UUID-1" })
    }

    static func expand(_ body: String) -> Result<Snippets.Expanded, Snippets.Problem> {
        Snippets.expand(body, file: "Reply.txt", context: context())
    }

    @Test(arguments: [
        (Snippets.BuiltIn.isoDate, "2026-12-30"),
        (.longDate, "December 30, 2026"),
        (.time, "14:22"),
        (.isoTimestamp, "2026-12-30T14:22:05-05:00"),
        (.unixTime, "1798658525"),
        // Wednesday 30 December 2026 is in ISO week 53 of 2026.
        (.isoWeek, "2026-W53"),
    ])
    func builtIns(builtIn: Snippets.BuiltIn, expected: String) {
        #expect(builtIn.text(at: Self.now, calendar: Self.calendar) == expected)
    }

    @Test(arguments: [
        ("Hi {selection}, see {clipboard}.", "Hi SEL, see CLIP."),
        ("{date}", "2026-12-30"),
        ("{date format=\"EEEE\"}", "Wednesday"),
        // Offsets across the month and year end.
        ("{date offset=\"+3d\"}", "2027-01-02"),
        ("{date offset=\"+2m\" format=\"MMM d\"}", "Feb 28"),
        ("{date offset=\"-1w\"}", "2026-12-23"),
        ("{date offset=\"+1y\"}", "2027-12-30"),
        ("{time offset=\"+10h\" format=\"yyyy-MM-dd HH:mm\"}", "2026-12-31 00:22"),
        ("{uuid} {epoch}", "UUID-1 1798658525"),
        ("{{literal}} braces", "{literal} braces"),
    ])
    func placeholders(body: String, expected: String) throws {
        #expect(try Self.expand(body).get().text == expected)
    }

    /// `{cursor}` is where the cursor lands: ← that many times after the paste.
    @Test func cursorCountsWhatComesAfterIt() throws {
        #expect(try Self.expand("Dear {cursor},\nThanks").get() == Snippets.Expanded(text: "Dear ,\nThanks", charactersAfterCursor: 8))
        #expect(try Self.expand("{cursor}abc").get().charactersAfterCursor == 3)
        #expect(try Self.expand("abc{cursor}").get().charactersAfterCursor == 0)
        #expect(try Self.expand("no marker").get().charactersAfterCursor == 0)
        // Emoji count as one each, as ← moves over them once.
        #expect(try Self.expand("{cursor}👋🏽!").get().charactersAfterCursor == 2)
    }

    /// A bad placeholder names its file and line.
    @Test(arguments: [
        ("line one\n{nope}", 2, "no placeholder called {nope}"),
        ("{date offset=\"3 days\"}", 1, "offset=\"3 days\" isn't like \"+3d\" or \"-1w\""),
        ("{uuid format=\"x\"}", 1, "{uuid} has no format=\"…\""),
        ("a\nb\n{cursor} and {cursor}", 3, "{cursor} more than once"),
        ("open { never closed", 1, "a { with no }"),
        ("{Bad Name}", 1, "can't read {Bad Name}"),
    ])
    func problems(body: String, line: Int, message: String) {
        guard case .failure(let problem) = Self.expand(body) else {
            Issue.record("expected a problem for \(body)")
            return
        }
        #expect(problem == Snippets.Problem(file: "Reply.txt", line: line, message: message))
        #expect(problem.description == "Reply.txt, line \(line): \(message)")
    }

    @Test func noClipboardIsEmpty() throws {
        #expect(try Snippets.expand("[{clipboard}]", file: "x", context: Self.context(clipboard: nil)).get().text == "[]")
    }

    /// One snippet a file (its name the snippet's), subfolders as groups, hidden files and
    /// other kinds of file skipped.
    @Test func foldersBecomeGroups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snippets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let work = root.appendingPathComponent("Work/Replies")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try "Hi".write(to: root.appendingPathComponent("Greeting.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent(".hidden.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: root.appendingPathComponent("photo.png"))
        try "Thanks".write(to: work.appendingPathComponent("Thanks.md"), atomically: true, encoding: .utf8)
        let library = Snippets.load(folder: root)
        #expect(library.entries.map(\.name) == ["Greeting"])
        #expect(library.groups.map(\.name) == ["Work"])
        #expect(library.group(at: "Work/Replies")?.entries.map(\.name) == ["Thanks"])
        #expect(library.group(at: "Nope") == nil)
        #expect(Snippets.load(folder: root.appendingPathComponent("missing")).entries.isEmpty)
    }
}

/// The Snippets wheel's pages and how a file becomes text.
struct SnippetWheelTests {
    typealias Entry = Snippets.Entry
    static let greeting = Entry(name: "Greeting", source: .file(URL(fileURLWithPath: "/x/Greeting.txt")))
    static let thanks = Entry(name: "Thanks", source: .file(URL(fileURLWithPath: "/x/Work/Thanks.txt")))
    static let library = Snippets.Group(name: "Snippets", path: "", entries: [greeting], groups: [
        Snippets.Group(name: "Work", path: "Work", entries: [thanks], groups: []),
    ])

    @Test func anEmptyFolderShowsTheBuiltIns() {
        let empty = Snippets.Group(name: "Snippets", path: "", entries: [], groups: [])
        #expect(SnippetWheel.commands(for: empty, at: "") == SnippetWheel.builtIns.map(TextCommand.snippet))
    }

    @Test func ownSnippetsFirstThenGroupsThenDates() {
        #expect(SnippetWheel.commands(for: Self.library, at: "") == [.snippet(Self.greeting), .snippetGroup("Work"), .snippetGroup(SnippetWheel.datesPath)])
        #expect(SnippetWheel.commands(for: Self.library, at: "Work") == [.snippet(Self.thanks), .snippetBack("")])
        #expect(SnippetWheel.commands(for: Self.library, at: SnippetWheel.datesPath) == SnippetWheel.builtIns.map(TextCommand.snippet) + [.snippetBack("")])
        #expect(SnippetWheel.commands(for: Self.library, at: "Gone").isEmpty)
        #expect(WheelItem.text(.snippetGroup("Work")).title == "Work ▸")
        #expect(WheelItem.text(.snippetGroup(SnippetWheel.datesPath)).title == "Dates & Times ▸")
    }

    @Test func aFileLosesItsFinalLineBreakAndKeepsTheRest() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snippet-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Dear {selection},\n\n{cursor}\n".write(to: file, atomically: true, encoding: .utf8)
        let expanded = try SnippetWheel.expand(Entry(name: "x", source: .file(file)), context: SnippetsTests.context(selection: "Sam")).get()
        #expect(expanded == Snippets.Expanded(text: "Dear Sam,\n\n", charactersAfterCursor: 0))
        guard case .failure(let problem) = SnippetWheel.expand(Entry(name: "x", source: .file(file.appendingPathExtension("missing"))), context: SnippetsTests.context()) else {
            Issue.record("a missing file should be a problem")
            return
        }
        #expect(problem.message == "couldn't read the file as UTF-8 text")
    }

    /// A built-in's format can be replaced by a stored pattern.
    @Test func builtInFormatsCanBeChanged() throws {
        let defaults = UserDefaults(suiteName: "OpenShelfTests.snippets.\(UUID())")!
        defaults.set("dd/MM/yyyy", forKey: "SnippetFormat.isoDate")
        let iso = Entry(name: "ISO Date", source: .builtIn(.isoDate))
        #expect(try SnippetWheel.expand(iso, context: SnippetsTests.context(), defaults: defaults).get().text == "30/12/2026")
        #expect(SnippetWheel.shortcut.displayString == "⌃⌥I")
    }
}
