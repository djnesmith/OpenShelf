import AppKit
import Testing
@testable import OpenShelf

/// Every name a wheel can show, measured with the wedge's real font at the
/// narrowest wedge a wheel draws (seven), so a long one is caught here
/// rather than cut off on screen.
struct WedgeLabelTests {
    static let narrowest = WheelGeometry(wedgeCount: WheelPaging.slotCount)

    static let textContexts = [
        TextContext(text: #"{"a":1}"#, hasRichText: true, canUndo: true),
        TextContext(text: "a: 1\nb: 2", hasRichText: false, canUndo: false),
        TextContext(text: "func f() {}", hasRichText: false, canUndo: true),
        TextContext(text: "prose", hasRichText: true, canUndo: true),
    ]

    /// Every wedge on the text wheel and each wheel under it.
    static var textItems: [WheelItem] {
        textContexts.flatMap { context in
            ([nil] + TextGroup.allCases.map(Optional.some)).flatMap { TextWheel.items(for: context, group: $0) }
        }
    }

    /// Every wedge a file wheel can show. An iWork format shows its app's
    /// icon, and a smaller label, only where the app is installed, so both.
    static var fileItems: [WheelItem] {
        let formats = OutputFormat.allCases.flatMap { format -> [WheelItem] in
            let plain = WheelItem(command: .convert(format), title: format.title, systemImage: nil)
            guard format.iWorkFormat != nil else { return [plain] }
            return [plain, WheelItem(command: .convert(format), title: format.title, systemImage: nil, appIconPath: "/Applications")]
        }
        return formats + FileTool.allCases.map(WheelItem.tool) + FileAction.allCases.map(WheelItem.action)
    }

    static func tooBig(_ items: [WheelItem]) -> [String] {
        let width = narrowest.labelWidth
        return items.filter { WedgeLabel.fontSize(for: $0.title, base: WedgeLabel.baseSize(for: $0), width: width) == nil }.map(\.title)
    }

    @Test func everyTextWedgeNameFits() {
        #expect(Self.textItems.count > 40)
        #expect(Self.tooBig(Self.textItems) == [])
    }

    @Test func everyFileWedgeNameFits() {
        #expect(Self.tooBig(Self.fileItems) == [])
    }

    @Test func aLongNameWrapsAtSpacesBeforeItShrinks() {
        let width = Self.narrowest.labelWidth
        #expect(WedgeLabel.lines("Remove Blank Lines", size: 9.5, width: width)?.count == 2)
        #expect(WedgeLabel.fontSize(for: "Trim", base: 9.5, width: width) == 9.5)
        // A sub-wheel's ▸ stays with the word before it.
        #expect(WedgeLabel.lines("Join & Split ▸", size: 9.5, width: width) == ["JOIN &", "SPLIT\u{00A0}▸"])
        #expect(WedgeLabel.lines("Check Safety", size: 9.5, width: width) == ["CHECK", "SAFETY"])
        #expect(WedgeLabel.fontSize(for: "Check Safety", base: 9.5, width: width) == 9.5)
        // The second line is held a little narrower, so "BLANK LINES" shrinks a step.
        let blank = WedgeLabel.fontSize(for: "Remove Blank Lines", base: 9.5, width: width)
        #expect(blank.map { $0 < 9.5 && $0 >= 9.5 * WedgeLabel.minimumScale } == true)
        // One word too wide for the wedge shrinks instead.
        let constant = WedgeLabel.fontSize(for: "CONSTANT_CASE", base: 9.5, width: width)
        #expect(constant.map { $0 < 9.5 && $0 >= 9.5 * WedgeLabel.minimumScale } == true)
        // One word too wide even at the smallest size doesn't fit.
        #expect(WedgeLabel.fontSize(for: "Supercalifragilistic", base: 9.5, width: width) == nil)
        // Three lines' worth doesn't fit either.
        #expect(WedgeLabel.fontSize(for: "Aaaa Bbbb Cccc Dddd Eeee Ffff Gggg", base: 9.5, width: width) == nil)
    }

    /// Halfway out across the petal, where its chord less the gap is 73.6 pt.
    @Test func theSevenWedgeLabelSitsMidPetalAndIs73PointsWide() {
        #expect(Self.narrowest.labelRadius == 94)
        #expect(abs(Self.narrowest.labelWidth - 73.57) < 0.01)
    }

    /// The search bar: the query (as long as the whole name it finds) then
    /// "· Name · Lines › Order", in the pill's 12 pt semibold, inside its
    /// maximum width less padding, magnifier and caret.
    @Test func everySearchResultFitsTheSearchBar() {
        // Padding, magnifier, caret and the three 5 pt gaps between them.
        let room = WheelGeometry.panelSide - 16 - 24 - 16 - 1.5 - 3 * 5
        let text = Self.textContexts.flatMap { TextWheel.searchCandidates(for: $0) }
        let files = Self.fileItems.flatMap { item in WheelKind.allCases.map { WheelSearchCandidate(item: item, path: [$0.shortTitle]) } }
        #expect(text.count > 40)
        let tooWide = (text + files).filter { Self.pillWidth($0.item.title.lowercased()) + Self.pillWidth("· \($0.label)") > room }.map(\.label)
        #expect(tooWide == [])
    }

    static func pillWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
    }
}
