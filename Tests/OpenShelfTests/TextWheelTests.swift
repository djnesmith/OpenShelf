import AppKit
import Foundation
import Testing
@testable import OpenShelf

struct TextSnifferTests {
    @Test(arguments: [
        (#"{"a": 1, "b": [true]}"#, DataTextFormat.json),
        ("[1, 2, 3]", .json),
        ("<root><a id=\"1\">x</a></root>", .xml),
        ("{:a 1 :b [1 2]}", .edn),
        ("[:div {:class \"x\"}]", .edn),
        ("#{:a :b}", .edn),
        ("title = \"x\"\n[owner]\nname = \"Tom\"", .toml),
        ("name: x\nitems:\n  - a\n  - b", .yaml),
        ("- a\n- key: b", .yaml),
    ])
    func dataFormats(text: String, expected: DataTextFormat) {
        #expect(TextSniffer.dataFormat(of: text) == expected)
    }

    @Test(arguments: ["Just a sentence.", "hello", "42", "", "Note: this is prose, not data.\nSecond line here."])
    func proseIsNotData(text: String) {
        #expect(TextSniffer.dataFormat(of: text) == nil)
    }

    @Test(arguments: [
        ("<!DOCTYPE html><html><body>x</body></html>", "html"),
        ("(defn f [x]\n(+ x 1))", "clj"),
        ("#!/bin/bash\necho hi", "sh"),
        ("SELECT a, b FROM t WHERE x = 1", "sql"),
        ("def f(x):\n  return x", "py"),
        ("import Foundation\nlet x = 1", "swift"),
        (#"{"a":1}"#, "json"),
        ("{:a 1}", "edn"),
    ])
    func codeExtensions(text: String, expected: String) {
        #expect(TextSniffer.codeExtension(for: text) == expected)
    }

    @Test func proseHasNoCodeExtension() {
        #expect(TextSniffer.codeExtension(for: "Dear Sam, thanks for the notes.") == nil)
    }
}

struct TextWheelTests {
    static func commands(_ items: [WheelItem]) -> [TextCommand] {
        items.compactMap { if case .text(let command) = $0.command { command } else { nil } }
    }

    @Test func proseGetsTrimCleanUpMarkdownAndMore() {
        let context = TextContext(text: "Some words here.", hasRichText: true, canUndo: false)
        #expect(Self.commands(TextWheel.items(for: context)) == [.tool(.trim), .tool(.cleanUp), .tool(.toMarkdown), .open(.more)])
    }

    @Test func dataGetsReindentAndConvertButNotMarkdown() {
        let context = TextContext(text: #"{"a":1}"#, hasRichText: true, canUndo: false)
        #expect(Self.commands(TextWheel.items(for: context)) == [.tool(.trim), .tool(.cleanUp), .tool(.reindent), .open(.convert), .open(.more)])
    }

    @Test func undoComesFirstWhenTheSelectionIsTheLastResult() {
        let context = TextContext(text: "x", hasRichText: false, canUndo: true)
        #expect(Self.commands(TextWheel.items(for: context)).first == .undo)
    }

    @Test func everyTextWheelFitsWithoutPaging() {
        let contexts = [
            TextContext(text: #"{"a":1}"#, hasRichText: true, canUndo: true),
            TextContext(text: "prose", hasRichText: true, canUndo: true),
        ]
        for context in contexts {
            for group in [nil, TextGroup.convert, .more] {
                let items = TextWheel.items(for: context, group: group)
                #expect(items.count <= WheelPaging.slotCount)
                #expect(WheelPaging.pageCount(forItemCount: items.count) == 1)
            }
        }
    }

    @Test func convertOffersEveryOtherFormatThenBack() {
        let context = TextContext(text: "a: 1\nb: 2", hasRichText: false, canUndo: false)
        #expect(context.dataFormat == .yaml)
        #expect(Self.commands(TextWheel.items(for: context, group: .convert)) == [.convert(.json), .convert(.edn), .convert(.xml), .convert(.toml), .back])
    }

    @Test func moreHoldsTheLayoutToolsThenBack() {
        let context = TextContext(text: "x", hasRichText: false, canUndo: false)
        #expect(Self.commands(TextWheel.items(for: context, group: .more)) == [
            .tool(.dedent), .tool(.indent), .tool(.outdent), .tool(.tabsSpaces), .tool(.trimLines), .tool(.straightenQuotes), .back,
        ])
    }

    @Test func modifiersChooseWhereTheResultGoes() {
        #expect(TextDelivery(modifiers: []) == .replace)
        #expect(TextDelivery(modifiers: .option) == .copy)
        #expect(TextDelivery(modifiers: .shift) == .shelf)
        #expect(TextDelivery(modifiers: [.option, .shift]) == .copy)
        #expect(TextDelivery(modifiers: .control) == .replace)
    }

    @Test func savedTextIsNamedByTimeAndKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-textfiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 0)
        let first = try TextFiles.save("one", fileExtension: "json", in: folder, now: now)
        let second = try TextFiles.save("two", fileExtension: "json", in: folder, now: now)
        #expect(first.pathExtension == "json")
        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }
}

struct TextHistoryTests {
    @Test func undoMatchesTheResultInTheSameApp() {
        var history = TextHistory()
        history.record(original: " a ", result: "a", bundleID: "com.apple.TextEdit")
        #expect(history.undoable(for: "a", in: "com.apple.TextEdit")?.original == " a ")
        #expect(history.undoable(for: "a", in: "com.apple.mail") == nil)
        #expect(history.undoable(for: " a ", in: "com.apple.TextEdit") == nil)
    }

    @Test func newestMatchWins() {
        var history = TextHistory()
        history.record(original: "first", result: "x", bundleID: "app")
        history.record(original: "second", result: "x", bundleID: "app")
        #expect(history.undoable(for: "x", in: "app")?.original == "second")
    }

    @Test func keepsOnlyTheLastTen() {
        var history = TextHistory()
        for index in 0..<15 { history.record(original: "o\(index)", result: "r\(index)", bundleID: nil) }
        #expect(history.entries.count == TextHistory.limit)
        #expect(history.entries.first?.original == "o14")
        #expect(history.undoable(for: "r4", in: nil) == nil)
        #expect(history.undoable(for: "r5", in: nil) != nil)
    }

    @Test func unchangedTextIsNotRecorded() {
        var history = TextHistory()
        history.record(original: "same", result: "same", bundleID: nil)
        #expect(history.entries.isEmpty)
    }

    @Test func undoneEntriesAreForgotten() throws {
        var history = TextHistory()
        history.record(original: "o", result: "r", bundleID: nil)
        let entry = try #require(history.undoable(for: "r", in: nil))
        history.remove(entry)
        #expect(history.undoable(for: "r", in: nil) == nil)
    }
}

@MainActor
struct HotkeyRouteTests {
    func route(_ bundleID: String? = "com.apple.TextEdit", secure: Bool = false, reads: [TextReader: SelectedTextRead]) async -> HotkeyRoute {
        await HotkeyRoute.choose(frontmostBundleID: bundleID, isSecureInputOn: secure, strategy: .for(bundleID: bundleID)) { reads[$0] ?? .unavailable }
    }

    @Test func finderKeepsItsFileWheel() async {
        #expect(await route("com.apple.finder", reads: [.accessibility: .text("x")]) == .finder)
    }

    @Test func firstReaderWithTextWins() async {
        #expect(await route(reads: [.accessibility: .text("a"), .copyShortcut: .text("b")]) == .text("a", from: .accessibility))
        #expect(await route(reads: [.accessibility: .nothingSelected, .copyShortcut: .text("b")]) == .text("b", from: .copyShortcut))
    }

    @Test func terminalsNeverPressKeys() async {
        var asked: [TextReader] = []
        let chosen = await HotkeyRoute.choose(frontmostBundleID: "com.googlecode.iterm2", isSecureInputOn: false, strategy: .for(bundleID: "com.googlecode.iterm2")) { asked.append($0); return $0 == .recentClipboard ? .text("copied") : .nothingSelected }
        #expect(chosen == .text("copied", from: .recentClipboard))
        #expect(!asked.contains(.copyShortcut))
    }

    @Test func emacsAsksEmacsFirst() async {
        #expect(await route("org.gnu.Emacs", reads: [.emacsClient: .text("region"), .accessibility: .text("ax")]) == .text("region", from: .emacsClient))
    }

    @Test func secureAndPermission() async {
        #expect(await route(secure: true, reads: [.accessibility: .text("pw")]) == .secureInput)
        #expect(await route(reads: [.accessibility: .notPermitted, .copyShortcut: .notPermitted]) == .askForAccessibility)
        #expect(await route("com.googlecode.iterm2", reads: [.accessibility: .notPermitted, .recentClipboard: .text("c")]) == .text("c", from: .recentClipboard))
        #expect(await route(reads: [:]) == .nothing)
    }

    @Test func terminalDeliveryCopiesUnlessControl() {
        #expect(TextDelivery(modifiers: [], strategy: .terminal) == .copy)
        #expect(TextDelivery(modifiers: .option, strategy: .terminal) == .copy)
        #expect(TextDelivery(modifiers: .control, strategy: .terminal) == .replace)
        #expect(TextDelivery(modifiers: .shift, strategy: .terminal) == .shelf)
        #expect(TextDelivery(modifiers: [], strategy: .guiEmacs) == .replace)
    }

    @Test func clipboardFreshness() {
        var f = ClipboardFreshness(changeCount: 5)
        let t = Date(timeIntervalSince1970: 1000)
        #expect(!f.isFresh(at: t))
        f.observe(changeCount: 6, at: t)
        #expect(f.isFresh(at: t.addingTimeInterval(60)))
        #expect(!f.isFresh(at: t.addingTimeInterval(61)))
    }

    @Test func emacsQuotingAndAnswers() {
        #expect(EmacsClient.lispString(#"/tmp/a"b\c"#) == #""/tmp/a\"b\\c""#)
        #expect(EmacsClient.answer(in: ["\"region\""]) == "region")
        #expect(EmacsClient.answer(in: ["noise"]) == nil)
    }

    @Test func nothingFoundNamesTheApp() {
        let toast = HotkeyRoute.nothingSelectedToast(appName: "iTerm2", strategy: .terminal, shortcut: nil)
        #expect(toast.title == "No selected text found in iTerm2")
        #expect(toast.subtitle == "Select text, ⌘C, then the shortcut")
    }
}
