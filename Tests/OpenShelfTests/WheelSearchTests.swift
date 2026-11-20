import AppKit
import Carbon.HIToolbox
import Testing
@testable import OpenShelf

struct WheelSearchTests {
    private let text = TextContext(text: "one\ntwo", hasRichText: false, canUndo: false)
    private var textCandidates: [WheelSearchCandidate] { TextWheel.searchCandidates(for: text) }

    private func titles(_ query: String, recent: [WheelCommand] = []) -> [String] {
        WheelSearch.results(for: query, in: textCandidates, recent: recent).map(\.item.title)
    }

    @Test(arguments: [
        ("sort", "Sort A–Z"),
        ("snake", "snake_case"),
        ("dedupe", "Remove Duplicates"),
        ("rbl", "Remove Blank Lines"),
        ("csv", "CSV → Table"),
        ("upper", "UPPER"),
        ("camel", "camelCase"),
        ("join sp", "Join with Spaces"),
        ("TITLE", "Title Case"),
    ])
    func bestMatchComesFirst(query: String, expected: String) {
        #expect(titles(query).first == expected, "\(titles(query).prefix(3))")
    }

    @Test func everyWordMustMatch() {
        #expect(titles("sort length") == ["Sort by Length"])
        #expect(titles("zzz").isEmpty)
        #expect(titles("").isEmpty)
    }

    @Test func lettersTogetherInATitleAlwaysMatch() {
        for (query, title) in [("ram", "frame rate"), ("py", "copy path"), ("lank", "remove blank lines")] {
            #expect(WheelSearch.score(query, in: title) != nil, "\(query) in \(title)")
        }
    }

    /// The scoring rules, one at a time: a run of letters, a word start, a prefix.
    @Test func scoringRewardsRunsWordStartsAndPrefixes() {
        #expect(WheelSearch.score("ab", in: "xab") == 4)      // gap of 1 (-1), then a run (+5)
        #expect(WheelSearch.score("c", in: "x case") == 6)    // gap of 2 (-2), word start (+8)
        #expect(WheelSearch.score("c", in: "abcdefg c") == 3) // skips to the word start; gap capped (-5)
        #expect(WheelSearch.score("ab", in: "abc") == 28)     // word start, run, prefix (+15)
        #expect(WheelSearch.score("ba", in: "abc") == nil)
        #expect(WheelSearch.score("", in: "abc") == nil)
    }

    @Test func accentsAndCaseFold() {
        let candidates = [WheelSearchCandidate(item: WheelItem(command: .action(.copyName), title: "Résumé Écrit", systemImage: nil))]
        #expect(WheelSearch.results(for: "resume ec", in: candidates).count == 1)
    }

    @Test func tiesGoToRecentThenCatalogueOrder() {
        // The three sorts share the keyword "sort"; recency decides among equals.
        let sorts = titles("sort").filter { $0.hasPrefix("Sort ") }
        #expect(Array(sorts.prefix(3)) == ["Sort A–Z", "Sort Natural", "Sort by Length"])
        let recent: [WheelCommand] = [.text(.tool(.sortByLength))]
        #expect(WheelSearch.score("sort", textCandidates.first { $0.item.title == "Sort by Length" }!)
            == WheelSearch.score("sort", textCandidates.first { $0.item.title == "Sort Natural" }!))
        let ranked = titles("sort", recent: recent)
        #expect(ranked.firstIndex(of: "Sort by Length")! < ranked.firstIndex(of: "Sort Natural")!)
    }

    @Test func textSearchReachesEverySubWheelOnceWithItsPath() {
        let candidates = textCandidates
        #expect(Set(candidates.map(\.item)).count == candidates.count)
        let tools = candidates.compactMap { candidate -> TextTool? in
            guard case .text(.tool(let tool)) = candidate.item.command else { return nil }
            return tool
        }
        // Prose without rich text: no Re-indent, Convert or To Markdown.
        #expect(Set(tools) == Set(TextTool.allCases).subtracting([.reindent, .toMarkdown]))
        let natural = candidates.first { $0.item.title == "Sort Natural" }
        #expect(natural?.label == "Sort Natural · Lines › Order")
        #expect(candidates.allSatisfy {
            if case .text(.open) = $0.item.command { return false }
            if case .text(.back) = $0.item.command { return false }
            return true
        })
    }

    @Test func searchFromASubWheelStaysInside() {
        let fromCase = TextWheel.searchCandidates(for: text, from: .textCase)
        #expect(fromCase.map(\.item.title).contains("snake_case"))
        #expect(!fromCase.map(\.item.title).contains("Sort A–Z"))
    }

    @Test func queryTypingSelectAllAndBackspace() {
        var query = WheelSearchQuery()
        query.type("s")
        query.type("o")
        #expect(query.text == "so")
        query.selectAll()
        #expect(query.isAllSelected)
        query.type("u")
        #expect(query.text == "u" && !query.isAllSelected)
        query.deleteBackward()
        #expect(query.isEmpty)
        query.selectAll()
        #expect(!query.isAllSelected)
        query.type("ab")
        query.selectAll()
        query.deleteBackward()
        #expect(query.isEmpty)
    }

    @Test func whatStartsAndContinuesASearch() {
        #expect(WheelSearchQuery.accepts("a", starting: true))
        #expect(WheelSearchQuery.accepts("7", starting: true))
        #expect(WheelSearchQuery.accepts("é", starting: true))
        #expect(!WheelSearchQuery.accepts(" ", starting: true))
        #expect(WheelSearchQuery.accepts(" ", starting: false))
        #expect(!WheelSearchQuery.accepts("\r", starting: false))
        #expect(!WheelSearchQuery.accepts("\u{1B}", starting: false))
        #expect(!WheelSearchQuery.accepts("", starting: true))
    }
}

/// The search driven through the wheel's own key handling, with key events
/// made in the test; nothing is sent to any app.
@MainActor
struct WheelSearchKeyTests {
    private func key(_ text: String, _ keyCode: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    private func type(_ text: String, into controller: WheelController) {
        for character in text { #expect(controller.handleKey(key(String(character), kVK_ANSI_A))) }
    }

    private func openTextWheel(_ controller: WheelController) -> [WheelItem] {
        let context = TextContext(text: "b\na", hasRichText: false, canUndo: false)
        let items = TextWheel.items(for: context)
        controller.presentForKeyboard(
            items: items, title: "Text", summary: "3 characters", hint: "", at: NSPoint(x: 400, y: 400),
            searchCandidates: TextWheel.searchCandidates(for: context)
        )
        return items
    }

    /// The preview follows the text wheel: told on opening, on every move and through
    /// More, with the wheel's frame and that it is a text wheel; told "closed" (no frame)
    /// as it closes (David, 2026-11-20: the pane must be there the whole time).
    @Test func thePreviewIsToldWhileTheTextWheelIsOpen() {
        let controller = WheelController()
        var calls: [(WheelItem?, NSRect?, Bool)] = []
        controller.onHighlightChange = { calls.append(($0, $1, $2)) }
        _ = openTextWheel(controller)
        #expect(calls.last?.1 != nil)
        #expect(calls.last?.2 == true)
        #expect(controller.handleKey(key("", kVK_RightArrow)))
        #expect(calls.last?.1 != nil)
        controller.endKeyboardMode(hidingWheel: true)
        #expect(calls.last?.1 == nil)
    }

    @Test func typingStartsASearchAndReturnRunsTheTopMatch() {
        let controller = WheelController()
        var ran: [WheelItem] = []
        controller.onDrop = { item, _, _, _ in ran.append(item) }
        let items = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        #expect(controller.model.items == items)

        type("sort", into: controller)
        #expect(controller.model.search?.text == "sort")
        #expect(controller.model.items.first?.title == "Sort A–Z")
        #expect(controller.model.highlightedSlot == 0)
        #expect(controller.model.searchLabels[.text(.tool(.sortAZ))] == "Sort A–Z · Lines")
        #expect(controller.model.searchResultLabel == "Sort A–Z · Lines")

        #expect(controller.handleKey(key("\r", kVK_Return)))
        #expect(ran.map(\.command) == [.text(.tool(.sortAZ))])
        #expect(controller.recentCommands.first == .text(.tool(.sortAZ)))
    }

    @Test func arrowsAndCommandNumbersPickAmongMatches() {
        let controller = WheelController()
        var ran: [WheelItem] = []
        controller.onDrop = { item, _, _, _ in ran.append(item) }
        _ = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        type("case", into: controller)
        let matches = controller.model.items
        #expect(matches.count > 2)
        #expect(controller.handleKey(key("", kVK_RightArrow)))
        #expect(controller.model.highlightedSlot == 1)
        #expect(controller.handleKey(key("3", kVK_ANSI_3, .command)))
        #expect(ran == [matches[2]])
    }

    @Test func backspaceToEmptyAndEscRestoreTheWheel() {
        let controller = WheelController()
        let items = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }

        type("up", into: controller)
        #expect(controller.model.items != items)
        #expect(controller.handleKey(key("", kVK_Delete)))
        #expect(controller.model.search?.text == "u")
        #expect(controller.handleKey(key("", kVK_Delete)))
        #expect(controller.model.search == nil)
        #expect(controller.model.items == items)

        type("zzz", into: controller)
        #expect(controller.model.items.isEmpty)
        #expect(controller.model.highlightedSlot == nil)
        #expect(controller.model.searchResultLabel == "No tool matches")
        // First Esc leaves the search; the wheel stays open.
        #expect(controller.handleKey(key("\u{1B}", kVK_Escape)))
        #expect(controller.model.search == nil)
        #expect(controller.model.items == items)
        #expect(controller.isInKeyboardMode)
        // The second closes it.
        #expect(controller.handleKey(key("\u{1B}", kVK_Escape)))
        #expect(!controller.isInKeyboardMode)
    }

    @Test func commandFOpensTheBarThenSelectsWhatItHolds() {
        let controller = WheelController()
        let items = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }

        #expect(controller.handleKey(key("f", kVK_ANSI_F, .command)))
        #expect(controller.model.search == WheelSearchQuery())
        #expect(controller.model.items == items)

        type("sort", into: controller)
        #expect(controller.handleKey(key("f", kVK_ANSI_F, .command)))
        #expect(controller.model.search?.isAllSelected == true)
        type("k", into: controller)
        #expect(controller.model.search?.text == "k")
        #expect(controller.model.items.first?.title == "kebab-case")
    }

    @Test func escapeAfterASearchRestoresTheHighlight() {
        let controller = WheelController()
        _ = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        #expect(controller.handleKey(key("", kVK_RightArrow)))
        #expect(controller.handleKey(key("", kVK_RightArrow)))
        let highlight = controller.model.highlightedSlot
        type("lo", into: controller)
        #expect(controller.model.highlightedSlot == 0)
        #expect(controller.handleKey(key("\u{1B}", kVK_Escape)))
        #expect(controller.model.highlightedSlot == highlight)
    }

    @Test func commandFThenBackspaceClearsTheSelectedQuery() {
        let controller = WheelController()
        let items = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        type("sort", into: controller)
        #expect(controller.handleKey(key("f", kVK_ANSI_F, .command)))
        #expect(controller.handleKey(key("", kVK_Delete)))
        #expect(controller.model.search == nil)
        #expect(controller.model.items == items)
    }

    @Test func manyMatchesPageAndTheNextLetterStartsOver() {
        let controller = WheelController()
        _ = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        type("e", into: controller)
        #expect(controller.model.pageCount > 1)
        #expect(controller.handleKey(key("0", kVK_ANSI_0, .command)))
        #expect(controller.model.page == 1)
        type("x", into: controller)
        #expect(controller.model.page == 0)
    }

    /// Only tools count as used; opening a sub-wheel doesn't push tools out of the recent list.
    @Test func openingASubWheelIsNotRecentUse() {
        let controller = WheelController()
        let items = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        #expect(items.last?.command == .text(.open(.more)))
        #expect(controller.handleKey(key("", kVK_LeftArrow)))
        #expect(controller.model.highlighted?.item == items.last)
        #expect(controller.handleKey(key("\r", kVK_Return)))
        #expect(controller.recentCommands.isEmpty)
    }

    @Test func modifiedLettersDoNotSearch() {
        let controller = WheelController()
        _ = openTextWheel(controller)
        defer { controller.endKeyboardMode(hidingWheel: true) }
        #expect(!controller.handleKey(key("ß", kVK_ANSI_S, .option)))
        #expect(!controller.handleKey(key("s", kVK_ANSI_S, .control)))
        #expect(!controller.handleKey(key("q", kVK_ANSI_Q, .command)))
        #expect(!controller.handleKey(key("F", kVK_ANSI_F, [.command, .shift])))
        #expect(controller.model.search == nil)
    }

    @Test func fileWheelsSearchEveryKindAndPage() {
        let controller = WheelController()
        let formats = Array(OutputFormat.allCases.prefix(10)).map(WheelItem.convert)
        controller.itemsProvider = { kind, _ in
            switch kind {
            case .convert: formats
            case .tools: [WheelItem.tool(.compress)]
            default: []
            }
        }
        var ran: [WheelItem] = []
        controller.onDrop = { item, _, _, _ in ran.append(item) }
        #expect(controller.presentForKeyboard(urls: [URL(fileURLWithPath: "/tmp/a.png")], at: NSPoint(x: 400, y: 400)))
        defer { controller.endKeyboardMode(hidingWheel: true) }
        let last = formats[9]
        type(last.title, into: controller)
        #expect(controller.model.items.first == last)
        #expect(controller.handleKey(key("\u{1B}", kVK_Escape)))
        #expect(controller.handleKey(key("f", kVK_ANSI_F, .command)))
        type("compress", into: controller)
        #expect(controller.model.items.first == WheelItem.tool(.compress))
        #expect(controller.model.searchLabels[WheelItem.tool(.compress).command]?.hasSuffix("· \(WheelKind.tools.shortTitle)") == true)
        #expect(controller.handleKey(key("\r", kVK_Return)))
        #expect(ran == [WheelItem.tool(.compress)])
    }

    private func flags(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_Shift)
        )!
    }

    /// ⇧ or ⌃ tapped mid-search would switch file wheels under the search; Tab
    /// leaves the search first, then switches.
    @Test func wheelSwitchesDuringASearch() {
        let controller = WheelController()
        let formats = Array(OutputFormat.allCases.prefix(3)).map(WheelItem.convert)
        let tools = [WheelItem.tool(.compress), WheelItem.tool(.crop)]
        controller.itemsProvider = { kind, _ in
            switch kind {
            case .convert: formats
            case .tools: tools
            case .actions: [WheelItem.action(.copyName)]
            }
        }
        #expect(controller.presentForKeyboard(urls: [URL(fileURLWithPath: "/tmp/a.png")], at: NSPoint(x: 400, y: 400)))
        defer { controller.endKeyboardMode(hidingWheel: true) }
        let start = controller.model.items
        type("c", into: controller)
        let filtered = controller.model.items
        // Every single modifier: whichever ones are wheel triggers, none switches now.
        for tap in [NSEvent.ModifierFlags.shift, .control, .option] {
            #expect(controller.handleKey(flags(tap)))
            #expect(controller.handleKey(flags([])))
        }
        #expect(controller.model.search?.text == "c")
        #expect(controller.model.items == filtered)

        #expect(controller.handleKey(key("\t", kVK_Tab)))
        #expect(controller.model.search == nil)
        #expect(controller.model.items != start)
        #expect([formats, tools, [WheelItem.action(.copyName)]].contains(controller.model.items))
    }
}
