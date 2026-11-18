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
            for group in [nil] + TextGroup.allCases.map(Optional.some) {
                let items = TextWheel.items(for: context, group: group)
                #expect(items.count <= WheelPaging.slotCount)
                #expect(WheelPaging.pageCount(forItemCount: items.count) == 1)
            }
        }
    }

    @Test func convertOffersEveryOtherFormatThenBack() {
        let context = TextContext(text: "a: 1\nb: 2", hasRichText: false, canUndo: false)
        #expect(context.dataFormat == .yaml)
        #expect(Self.commands(TextWheel.items(for: context, group: .convert)) == [.convert(.json), .convert(.edn), .convert(.xml), .convert(.toml), .back(nil)])
    }

    @Test func moreLeadsToLinesCaseAndIndent() {
        let context = TextContext(text: "x", hasRichText: false, canUndo: false)
        #expect(Self.commands(TextWheel.items(for: context, group: .more)) == [
            .open(.lines), .open(.textCase), .open(.indentation), .tool(.trimLines), .tool(.straightenQuotes), .back(nil),
        ])
        #expect(Self.commands(TextWheel.items(for: context, group: .lines)) == [
            .tool(.sortAZ), .tool(.removeDuplicates), .tool(.removeBlankLines), .open(.order), .open(.joinSplit), .open(.lists), .back(.more),
        ])
        #expect(Self.commands(TextWheel.items(for: context, group: .textCase)) == [
            .tool(.upperCase), .tool(.lowerCase), .tool(.titleCase), .tool(.sentenceCase), .open(.codeCase), .back(.more),
        ])
    }

    @Test func backReturnsToTheWheelThatOpenedTheGroup() {
        // JSON, so Convert ▸ is on the first wheel too.
        let context = TextContext(text: "{\"a\": 1}", hasRichText: false, canUndo: false)
        var opened: [TextGroup: TextGroup?] = [:]
        for parent in [nil] + TextGroup.allCases.map(Optional.some) {
            for case .open(let child) in Self.commands(TextWheel.items(for: context, group: parent)) {
                #expect(opened[child] == nil, "\(child) opens from two wheels")
                opened[child] = parent
            }
        }
        for group in TextGroup.allCases {
            #expect(opened[group] == .some(group.parent), "\(group)")
            #expect(Self.commands(TextWheel.items(for: context, group: group)).last == .back(group.parent))
        }
    }

    /// Every tool is on exactly one wheel, so none is lost when groups move.
    @Test func everyToolIsOnOneWheel() {
        let context = TextContext(text: "{\"a\": 1}", hasRichText: true, canUndo: false)
        var found: [TextTool] = []
        for group in [nil] + TextGroup.allCases.map(Optional.some) {
            for case .tool(let tool) in Self.commands(TextWheel.items(for: context, group: group)) { found.append(tool) }
        }
        // To Markdown is only offered for prose, which this JSON isn't.
        #expect(found.sorted { "\($0)" < "\($1)" } == TextTool.allCases.filter { $0 != .toMarkdown }.sorted { "\($0)" < "\($1)" })
    }

    /// Each wedge runs its own tool: one input, every tool's answer.
    @Test(arguments: [
        (TextTool.sortAZ, "b\nA\nb\n", "A\nb\nb\n"),
        (.sortNatural, "x10\nx9", "x9\nx10"),
        (.sortByLength, "ccc\na", "a\nccc"),
        (.reverseLines, "1\n2", "2\n1"),
        (.removeDuplicates, "a\na", "a"),
        (.removeBlankLines, "a\n\nb", "a\nb"),
        (.numberLines, "a\nb", "1. a\n2. b"),
        (.markdownList, "a", "- a"),
        (.markdownTable, "a,b", "| a | b |\n| --- | --- |"),
        (.joinWithCommas, "a\nb", "a, b"),
        (.joinWithSpaces, "a\nb", "a b"),
        (.splitAtCommas, "a, b", "a\nb"),
        (.splitAtSpaces, "a b", "a\nb"),
        (.quoteLines, "a", "\"a\""),
        (.unquoteLines, "'a'", "a"),
        (.addCommas, "a\nb", "a,\nb"),
        (.upperCase, "Big deal", "BIG DEAL"),
        (.lowerCase, "Big Deal", "big deal"),
        (.titleCase, "big deal", "Big Deal"),
        (.sentenceCase, "BIG DEAL", "Big deal"),
        (.camelCase, "big deal", "bigDeal"),
        (.pascalCase, "big deal", "BigDeal"),
        (.snakeCase, "big deal", "big_deal"),
        (.kebabCase, "big deal", "big-deal"),
        (.constantCase, "big deal", "BIG_DEAL"),
    ])
    func eachToolRunsItsOwnTransform(tool: TextTool, text: String, expected: String) {
        #expect(tool.apply(to: text) == expected)
    }

    @Test func everyWedgeHasASymbol() {
        let context = TextContext(text: "x", hasRichText: false, canUndo: true)
        for group in [nil] + TextGroup.allCases.map(Optional.some) {
            // Convert's format wedges are words, with no symbol.
            for item in TextWheel.items(for: context, group: group) where group != .convert {
                #expect(NSImage(systemSymbolName: item.systemImage ?? "", accessibilityDescription: nil) != nil, "\(item.title)")
            }
        }
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
        let toast = HotkeyRoute.nothingSelectedToast(appName: "Notes", strategy: .standard, shortcut: nil)
        #expect(toast.title == "No selected text found in Notes")
        #expect(toast.subtitle == "Select text, or files in Finder")
    }

    @Test func terminalsSayCopyFirst() {
        let toast = HotkeyRoute.nothingSelectedToast(appName: "iTerm2", strategy: .terminal, shortcut: .defaultOpenWheel)
        #expect(toast.title == "Copy first: ⌘C, then ⌃⌥Space")
        #expect(toast.subtitle == "OpenShelf can't see a terminal's selection")
        let noShortcut = HotkeyRoute.nothingSelectedToast(appName: "iTerm2", strategy: .terminal, shortcut: nil)
        #expect(noShortcut.title == "Copy first: ⌘C, then the shortcut")
    }
}
