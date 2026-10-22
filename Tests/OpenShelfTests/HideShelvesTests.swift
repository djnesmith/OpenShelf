import AppKit
import Foundation
import Testing
@testable import OpenShelf

/// Hide Shelves / Show Shelves and the expanded default, on real shelf
/// windows, saving to a temporary file rather than the user's shelves.
@MainActor
struct HideShelvesTests {
    let store = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-shelves-\(UUID().uuidString).json")

    func files(_ count: Int) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-hide-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try (1...count).map { number in
            let url = folder.appendingPathComponent("File \(number).txt")
            try "x".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    @Test func restoredShelvesKeepTheirSavedView() throws {
        let urls = try files(2)
        let snapshot = ShelfSnapshot(
            items: urls.map { ShelfSnapshot.Item(path: $0.path, bookmark: nil) },
            frame: CGRect(x: 100, y: 100, width: 140, height: 160), dockedEdge: nil, isExpanded: false, viewMode: .grid
        )
        try ShelfStore.save([snapshot], to: store)
        let manager = ShelfManager(storeURL: store)
        manager.restoreSavedShelves()
        defer { manager.closeAll() }
        #expect(manager.openShelves.map(\.isExpanded) == [false])
    }

    @Test func hidingKeepsEveryShelfAndShowingBringsThemBack() throws {
        let manager = ShelfManager(storeURL: store)
        defer { manager.closeAll() }
        let first = manager.newShelf(with: try files(2), near: NSPoint(x: 300, y: 300))
        let second = manager.newShelf(with: try files(3), near: NSPoint(x: 700, y: 300))
        let controllers = manager.openShelves.compactMap { shelf in NSApp.windows.compactMap { $0.windowController as? ShelfWindowController }.first { $0.shelf === shelf } }
        #expect(controllers.count == 2 && controllers.allSatisfy(\.isPanelVisible))
        let frames = controllers.map(\.frameShown)

        manager.toggleHidden()
        #expect(manager.areHidden)
        #expect(controllers.allSatisfy { !$0.isPanelVisible && $0.isUserHidden })
        // Still open, with their files.
        #expect(manager.openShelves.count == 2 && first.items.count == 2 && second.items.count == 3)
        manager.saveNow()
        #expect(ShelfStore.load(from: store).count == 2)

        manager.toggleHidden()
        #expect(!manager.areHidden)
        #expect(controllers.allSatisfy { $0.isPanelVisible && !$0.isUserHidden })
        #expect(controllers.map(\.frameShown) == frames)
    }

    @Test func aNewShelfOrDropWhileHiddenShowsThemAll() throws {
        let manager = ShelfManager(storeURL: store)
        defer { manager.closeAll() }
        manager.newShelf(with: try files(1), near: NSPoint(x: 300, y: 300))
        manager.hideAll()
        manager.addToRecentShelf(try files(1))
        #expect(!manager.areHidden)
        manager.hideAll()
        manager.newShelf(with: try files(1), near: NSPoint(x: 600, y: 300))
        #expect(!manager.areHidden && manager.openShelves.count == 2)
    }

    @Test func closingEverythingWhileHiddenEndsHiding() throws {
        let manager = ShelfManager(storeURL: store)
        manager.newShelf(with: try files(1), near: NSPoint(x: 300, y: 300))
        manager.hideAll()
        manager.closeAll()
        #expect(!manager.areHidden && !manager.hasShelves)
        // With nothing open there's nothing to hide.
        manager.hideAll()
        #expect(!manager.areHidden)
    }
}
