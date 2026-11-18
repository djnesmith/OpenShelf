import Testing
@testable import OpenShelf

/// The label and search bar above the wheel, at their widest real content,
/// measured against the panel.
struct PillTextTests {
    /// A copied first line of the widest letters, and one in CJK.
    static let copiedNames = [
        TextWheel.title(for: String(repeating: "W", count: 40), from: .recentClipboard),
        TextWheel.title(for: String(repeating: "漢", count: 40), from: .recentClipboard),
    ]

    static var allItems: [WheelItem] { WedgeLabelTests.textItems + WedgeLabelTests.fileItems }

    @Test func theLabelNeverOutgrowsThePanelAndKeepsTheToolName() {
        let names = Self.copiedNames + ["Text"] + TextGroup.allCases.map(\.title) + WheelKind.allCases.map(\.shortTitle)
        for name in names {
            for title in Self.allItems.map(\.title) + ["More · 2 of 2", "Back · 2 of 2"] {
                let label = PillText.label(name: name, title)
                #expect(PillText.width(label) <= PillText.room, "\(label)")
                #expect(label.hasSuffix(" · \(title)"), "\(label)")
            }
        }
    }

    @Test func aLongCopiedNameIsCutInTheMiddle() {
        let label = PillText.label(name: Self.copiedNames[0], "Remove Blank Lines")
        #expect(label.hasPrefix("Copied: WW"))
        #expect(label.contains("…"))
        #expect(label.hasSuffix("W… · Remove Blank Lines") || label.hasSuffix("W · Remove Blank Lines"))
        // A short one is left alone.
        #expect(PillText.label(name: "Copied: hello", "Trim") == "Copied: hello · Trim")
        #expect(PillText.label(name: nil, "Trim") == "Trim")
    }

    /// The pill is 24 pt of padding wider than its text, and stays 16 pt
    /// inside the panel; the search bar also holds its magnifier (16),
    /// caret or selection padding (4) and three 5 pt gaps.
    @Test func theRoomIsThePanelLessThePillsOwnParts() {
        #expect(WheelGeometry.panelSide == 416)
        #expect(PillText.room == 376)
        #expect(PillText.searchRoom == 341)
    }

    @Test func aNameWithNoRoomLeftIsDropped() {
        var label = "W"
        while PillText.width(label + "W") + PillText.width(" · …") <= PillText.room { label += "W" }
        label += "W"
        #expect(PillText.label(name: "Copied: hello there", label) == label)
    }

    @Test func everyHintFits() {
        let hints = [KeyboardWheelHint.options, KeyboardWheelHint.search]
            + [true, false].flatMap { canSwitch in [true, false].map { KeyboardWheelHint.opening(canSwitch: canSwitch, hasOptions: $0) } }
        for hint in hints {
            #expect(PillText.shorten(hint, toFit: PillText.room, at: .tail) == hint)
        }
    }

    /// A long query and the longest match: the path is cut first, then the
    /// start of the query, and the tool's name stays whole.
    @Test func theSearchBarNeverOutgrowsThePanelAndKeepsTheToolName() {
        let longQuery = String(repeating: "w", count: 80)
        let candidates = WedgeLabelTests.textContexts.flatMap { TextWheel.searchCandidates(for: $0) }
        for candidate in candidates {
            for query in [longQuery, String(repeating: "w", count: 30), candidate.item.title] {
                let fitted = PillText.search(query: query, result: candidate.label)
                let result = try! #require(fitted.result)
                #expect(PillText.width(fitted.query) + PillText.width("· \(result)") <= PillText.searchRoom, "\(fitted)")
                #expect(result.hasPrefix(candidate.item.title), "\(fitted)")
            }
        }
    }

    @Test func theSearchBarCutsThePathBeforeTheQuery() {
        // As long as leaves room for "Lines…" but not the whole path.
        var mid = "w"
        while PillText.width(mid + "w") + PillText.width("· Remove Blank Lines · Lines…") <= PillText.searchRoom { mid += "w" }
        let fitted = PillText.search(query: mid, result: "Remove Blank Lines · Lines › Lists")
        #expect(fitted.query == mid)
        #expect(fitted.result?.hasPrefix("Remove Blank Lines · Lines") == true)
        #expect(fitted.result?.hasSuffix("…") == true)

        let long = String(repeating: "w", count: 80)
        let cut = PillText.search(query: long + "x", result: "Remove Blank Lines · Lines › Lists")
        #expect(cut.result == "Remove Blank Lines")
        #expect(cut.query.hasPrefix("…") && cut.query.hasSuffix("wx"))
    }

    @Test func shortenCutsWhereAsked() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let width = PillText.width("abcdefgh…")
        #expect(PillText.shorten(text, toFit: width, at: .tail).hasPrefix("abc"))
        #expect(PillText.shorten(text, toFit: width, at: .head).hasSuffix("xyz"))
        let middle = PillText.shorten(text, toFit: width, at: .middle)
        #expect(middle.hasPrefix("ab") && middle.hasSuffix("z") && middle.contains("…"))
        #expect(PillText.width(middle) <= width)
        #expect(PillText.shorten(text, toFit: 1000, at: .middle) == text)
        #expect(PillText.shorten(text, toFit: 1, at: .middle) == "")
    }
}
