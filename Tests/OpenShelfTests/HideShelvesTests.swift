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

    /// Upstream's watched folders: every arrival shows hidden shelves, not only the first.
    @Test func everyWatchedFolderArrivalWhileHiddenShowsThemAll() throws {
        let manager = ShelfManager(storeURL: store)
        defer { manager.closeAll() }
        let folder = UUID()
        manager.addArrivals(try files(1), fromWatchedFolder: folder)
        manager.hideAll()
        manager.addArrivals(try files(1), fromWatchedFolder: folder)
        #expect(!manager.areHidden && manager.openShelves.count == 1)
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

    // MARK: The wheel shortcut on shelf items

    @Test func aMoveFromTheWheelMovesTheShelfItemsToo() throws {
        let manager = ShelfManager(storeURL: store)
        defer { manager.closeAll() }
        let urls = try files(3)
        let shelf = manager.newShelf(with: urls, near: NSPoint(x: 300, y: 300))
        shelf.selection = Set(shelf.items.prefix(2).map(\.id))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-moved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = FileActions.transfer(Array(urls.prefix(2)), into: target, operation: .move) { _, _, _ in
            FileActions.ConflictDecision(choice: .skip)
        }
        manager.relocate(result.moves)
        // Same order, the moved two now in the target folder, still selected and present.
        #expect(shelf.items.map(\.url.lastPathComponent) == ["File 1.txt", "File 2.txt", "File 3.txt"])
        #expect(shelf.items.prefix(2).allSatisfy { $0.url.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL && $0.exists })
        #expect(shelf.selectedItems.map(\.url.lastPathComponent) == ["File 1.txt", "File 2.txt"])
        #expect(shelf.items[2].url == urls[2].standardizedFileURL)
    }
}
