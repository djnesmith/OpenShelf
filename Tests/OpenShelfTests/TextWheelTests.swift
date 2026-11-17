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
    func route(
        _ bundleID: String? = "com.apple.TextEdit",
        secure: Bool = false,
        read: SelectedTextRead,
        copied: String? = nil
    ) async -> HotkeyRoute {
        await HotkeyRoute.choose(frontmostBundleID: bundleID, isSecureInputOn: secure, read: { read }, copy: { copied })
    }

    @Test func finderAlwaysKeepsItsFileWheel() async {
        #expect(await route("com.apple.finder", read: .text("renaming"), copied: "x") == .finder)
        #expect(await route("com.apple.finder", secure: true, read: .notPermitted) == .finder)
    }

    @Test func finderNeverReadsTheSelection() async {
        var didRead = false
        _ = await HotkeyRoute.choose(frontmostBundleID: "com.apple.finder", isSecureInputOn: false, read: { didRead = true; return .unavailable }, copy: { nil })
        #expect(!didRead)
    }

    @Test func selectedTextOpensTheTextWheel() async {
        #expect(await route(read: .text("hello")) == .text("hello"))
    }

    @Test func accessibilityTextNeverTriesCopy() async {
        var didCopy = false
        let chosen = await HotkeyRoute.choose(frontmostBundleID: "x", isSecureInputOn: false, read: { .text("a") }, copy: { didCopy = true; return "b" })
        #expect(chosen == .text("a"))
        #expect(!didCopy)
    }

    @Test func secureInputIsRefusedBeforeReading() async {
        var didRead = false
        let chosen = await HotkeyRoute.choose(frontmostBundleID: "x", isSecureInputOn: true, read: { didRead = true; return .text("pw") }, copy: { "pw" })
        #expect(chosen == .secureInput)
        #expect(!didRead)
        #expect(await route(read: .secure) == .secureInput)
    }

    @Test func withoutAccessibilityItAsks() async {
        #expect(await route(read: .notPermitted, copied: "x") == .askForAccessibility)
    }

    @Test func emptySelectionIsNothing() async {
        #expect(await route(read: .nothingSelected, copied: "x") == .nothing)
        #expect(await route(read: .text("")) == .nothing)
    }

    @Test func unreadableAppsFallBackToCopy() async {
        #expect(await route(read: .unavailable, copied: "from copy") == .text("from copy"))
        #expect(await route(read: .unavailable, copied: nil) == .nothing)
        #expect(await route(read: .unavailable, copied: "") == .nothing)
    }
}
