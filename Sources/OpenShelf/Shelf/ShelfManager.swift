import AppKit
import Observation

/// Creates shelves, keeps track of which one was used most recently, and saves
/// them so they come back after a relaunch.
@MainActor
@Observable
final class ShelfManager {
    /// Ordered from least to most recently used.
    private var controllers: [ShelfWindowController] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let storeURL: URL

    /// Whether Hide Shelves has put every shelf out of sight. They stay open,
    /// with their files and places, until Show Shelves; a relaunch shows them.
    private(set) var areHidden = false

    init(storeURL: URL = ShelfStore.defaultURL) {
        self.storeURL = storeURL
    }

    var hasShelves: Bool { !controllers.isEmpty }

    /// Open shelves, most recently used first, for the menu-bar menu.
    var openShelves: [Shelf] { controllers.reversed().map(\.shelf) }

    /// The selected files of the shelf that has keyboard focus, or nil when none has.
    var keyShelfSelection: [URL]? {
        controllers.first { $0.window?.isKeyWindow == true }.map { $0.shelf.selectedItems.map(\.url) }
    }

    /// The selected files of the most recently used shelf.
    var recentShelfSelection: [URL] {
        controllers.last?.shelf.selectedItems.map(\.url) ?? []
    }

    /// Puts every shelf out of sight, edge tabs too, keeping each as it is.
    func hideAll() {
        guard hasShelves else { return }
        areHidden = true
        for controller in controllers {
            controller.setUserHidden(true)
        }
    }

    /// Brings hidden shelves back as they were: where they were, and those
    /// tucked behind an edge still tucked there.
    func unhideAll() {
        guard areHidden else { return }
        areHidden = false
        for controller in controllers {
            controller.setUserHidden(false)
        }
    }

    /// The menu's Hide Shelves / Show Shelves.
    func toggleHidden() {
        areHidden ? unhideAll() : hideAll()
    }

    /// Brings every shelf to the front, sliding out any hidden at an edge, and
    /// focuses the most recently used one.
    func showAll() {
        unhideAll()
        for controller in controllers {
            controller.bringForward(focus: controller === controllers.last)
        }
    }

    /// Showing one shelf, from the menu, brings the others back too.
    func show(_ shelf: Shelf) {
        unhideAll()
        controllers.first { $0.shelf === shelf }?.bringForward(focus: true)
    }

    /// A new shelf while shelves are hidden brings them all back with it.
    @discardableResult
    func newShelf(with urls: [URL] = [], near location: NSPoint = NSEvent.mouseLocation) -> Shelf {
        unhideAll()
        let shelf = Shelf()
        shelf.add(urls)
        open(ShelfWindowController(shelf: shelf, near: location))
        return shelf
    }

    /// Adding files while shelves are hidden brings them all back, so the
    /// files land somewhere they can be seen.
    func addToRecentShelf(_ urls: [URL]) {
        guard let recent = controllers.last else {
            newShelf(with: urls)
            return
        }
        unhideAll()
        recent.shelf.add(urls)
        recent.present()
    }

    /// Updates every open reference after files move through the Actions wheel.
    func relocate(_ moves: [URL: URL]) {
        guard !moves.isEmpty else { return }
        for controller in controllers { controller.shelf.relocate(moves) }
        scheduleSave()
    }

    func closeAll() {
        for controller in controllers {
            controller.dismiss()
        }
    }

    // MARK: Saving and restoring

    /// Reopens the shelves saved at the end of the last session. Files that no
    /// longer exist are skipped, and shelves left with nothing aren't reopened.
    func restoreSavedShelves() {
        for snapshot in ShelfStore.load(from: storeURL) {
            let urls = snapshot.items.compactMap { ShelfStore.resolve($0) }
            guard !urls.isEmpty else { continue }
            let shelf = Shelf()
            shelf.add(urls)
            shelf.isExpanded = snapshot.isExpanded
            shelf.viewMode = snapshot.viewMode
            shelf.dockedEdge = snapshot.dockedEdge
            open(ShelfWindowController(shelf: shelf, near: NSEvent.mouseLocation, restoringFrame: snapshot.frame))
        }
        scheduleSave()
    }

    /// Writes every open shelf to disk right away, e.g. when quitting.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? ShelfStore.save(controllers.compactMap(\.snapshot), to: storeURL)
    }

    /// Coalesces bursts of changes (resizing, moving, adding files) into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func open(_ controller: ShelfWindowController) {
        controller.onClose = { [weak self] closed in
            // Closing the last hidden shelf (Close All) leaves nothing hidden.
            if self?.controllers.count == 1 { self?.areHidden = false }
            self?.controllers.removeAll { $0 === closed }
            self?.scheduleSave()
        }
        controller.onBecomeKey = { [weak self] active in
            self?.markRecentlyUsed(active)
        }
        controller.onStateChange = { [weak self] in
            self?.scheduleSave()
        }
        controllers.append(controller)
        controller.present()
        scheduleSave()
    }

    private func markRecentlyUsed(_ controller: ShelfWindowController) {
        guard let index = controllers.firstIndex(where: { $0 === controller }) else { return }
        controllers.append(controllers.remove(at: index))
    }
}
