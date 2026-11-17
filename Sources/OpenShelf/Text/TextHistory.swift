import Foundation

/// The last few text changes, in memory only and gone on quit, so a change
/// can be undone from OpenShelf even where the app's own ⌘Z can't.
struct TextHistory {
    struct Entry: Equatable {
        let original: String
        let result: String
        /// The app the text was changed in.
        let bundleID: String?
    }

    static let limit = 10

    private(set) var entries: [Entry] = []

    /// Records a change, newest first. Text from a secure field never gets here.
    mutating func record(original: String, result: String, bundleID: String?) {
        guard original != result else { return }
        entries.insert(Entry(original: original, result: result, bundleID: bundleID), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// The newest change whose result is exactly `selection`: selecting what
    /// OpenShelf just wrote offers to put the original back.
    func undoable(for selection: String, in bundleID: String?) -> Entry? {
        entries.first { $0.result == selection && $0.bundleID == bundleID }
    }

    /// Forgets an entry once it has been undone, so Undo doesn't come back for it.
    mutating func remove(_ entry: Entry) {
        if let index = entries.firstIndex(of: entry) { entries.remove(at: index) }
    }
}
