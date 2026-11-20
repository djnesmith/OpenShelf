import Foundation
import Testing
@testable import OpenShelf

/// Recent tools first and favourites on the first text wheel (ROADMAP C7).
struct TextRecentsTests {
    static func commands(_ items: [WheelItem]) -> [TextCommand] {
        items.compactMap { if case .text(let command) = $0.command { command } else { nil } }
    }

    static let plain = TextContext(text: "hello world", hasRichText: false, canUndo: false)

    @Test func theLastThreeToolsComeFirstInFreeSlots() {
        let items = TextWheel.items(for: Self.plain, recent: [.sortAZ, .upperCase, .trim, .lowerCase])
        // Trim was already on the wheel: it moves to the front without taking a slot.
        #expect(Self.commands(items) == [.tool(.sortAZ), .tool(.upperCase), .tool(.trim), .edit, .tool(.cleanUp), .open(.more)])
        #expect(items.count <= WheelPaging.slotCount)
    }

    /// With no free slot (Undo, Re-indent and Convert all showing), recents only reorder.
    @Test func neverPages() {
        let full = TextContext(text: "{\"a\": 1}", hasRichText: false, canUndo: true)
        let items = TextWheel.items(for: full, recent: [.sortAZ, .cleanUp, .upperCase])
        #expect(items.count <= WheelPaging.slotCount)
        // Clean Up, already there, moves to the front, ahead of Edit.
        let order = Self.commands(items)
        #expect(order.firstIndex(of: .tool(.cleanUp))! < order.firstIndex(of: .edit)!)
        #expect(Self.commands(items).first == .undo)
        #expect(Self.commands(items).last == .open(.more))
    }

    @Test func favouritesReplaceTrimAndCleanUp() {
        let items = TextWheel.items(for: Self.plain, favorites: [.sortAZ, .removeDuplicates])
        #expect(Self.commands(items) == [.edit, .tool(.sortAZ), .tool(.removeDuplicates), .open(.more)])
        // More than four: the first four.
        let many = TextWheel.items(for: Self.plain, favorites: [.upperCase, .lowerCase, .titleCase, .sentenceCase, .trim])
        #expect(Self.commands(many) == [.edit, .tool(.upperCase), .tool(.lowerCase), .tool(.titleCase), .tool(.sentenceCase), .open(.more)])
    }

    @Test func recentsAreKeptNewestFirstWithoutRepeats() {
        let defaults = UserDefaults(suiteName: "OpenShelfTests.recents.\(UUID())")!
        TextRecents.record(.trim, defaults)
        TextRecents.record(.upperCase, defaults)
        TextRecents.record(.trim, defaults)
        #expect(TextRecents.load(defaults) == [.trim, .upperCase])
        for tool in TextTool.allCases { TextRecents.record(tool, defaults) }
        #expect(TextRecents.load(defaults).count == TextRecents.kept)
        TextFavorites.save([.sortAZ, .upperCase, .lowerCase, .titleCase, .sentenceCase], defaults)
        #expect(TextFavorites.load(defaults) == [.sortAZ, .upperCase, .lowerCase, .titleCase])
        // Names that are no longer tools are dropped.
        defaults.set(["upperCase", "gone"], forKey: TextRecents.key)
        #expect(TextRecents.load(defaults) == [.upperCase])
    }
}
