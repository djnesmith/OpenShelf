import AppKit

/// When the clipboard last changed, from a count that only goes up. Pure,
/// so the freshness rule is tested with a fake clock.
struct ClipboardFreshness {
    /// How recent a copy has to be for the text wheel to use it.
    static let window: TimeInterval = 60

    private(set) var changeCount: Int
    /// Nil until a change is seen while OpenShelf is running: an older copy
    /// is of unknown age and never counts as fresh.
    private(set) var changedAt: Date?

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    mutating func observe(changeCount: Int, at now: Date) {
        guard changeCount != self.changeCount else { return }
        self.changeCount = changeCount
        changedAt = now
    }

    /// OpenShelf put the user's clipboard back after borrowing it: that's
    /// their old copy, not a new one, so its age doesn't reset.
    mutating func adopt(changeCount: Int) {
        self.changeCount = changeCount
    }

    func isFresh(at now: Date, window: TimeInterval = Self.window) -> Bool {
        guard let changedAt else { return false }
        return now.timeIntervalSince(changedAt) <= window
    }
}

/// Watches the clipboard's change count once a second, as clipboard managers
/// do, so "what you just copied" can be told from an old copy. Reads only the
/// count, never the contents, until the text wheel asks.
@MainActor
final class ClipboardWatcher {
    static let shared = ClipboardWatcher()

    private let pasteboard = NSPasteboard.general
    private var freshness: ClipboardFreshness
    private var timer: Timer?

    private init() {
        freshness = ClipboardFreshness(changeCount: NSPasteboard.general.changeCount)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { ClipboardWatcher.shared.poll() }
        }
    }

    func poll(now: Date = .now) {
        freshness.observe(changeCount: pasteboard.changeCount, at: now)
    }

    private var beforeBorrow: ClipboardFreshness?

    /// OpenShelf is about to borrow the clipboard (⌘C to read a selection, or
    /// a paste): its own writes and the restore must not look like a new copy.
    func willBorrow() {
        poll()
        beforeBorrow = freshness
    }

    /// The user's clipboard is back: it keeps the age it had before.
    func didRestore() {
        guard var saved = beforeBorrow else { return }
        saved.adopt(changeCount: pasteboard.changeCount)
        freshness = saved
        beforeBorrow = nil
    }

    /// The clipboard's text if it was copied in the last minute.
    func recentText(now: Date = .now) -> String? {
        poll(now: now)
        guard freshness.isFresh(at: now) else { return nil }
        return pasteboard.string(forType: .string)
    }
}
