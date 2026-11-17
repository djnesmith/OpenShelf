import Foundation

/// Borrows the clipboard to read a selection with ⌘C or to put a result in
/// place with ⌘V, and gives it back afterwards.
///
/// Paste is the default way back in because the app treats it as an ordinary
/// edit, so its own ⌘Z undoes it; setting the text through Accessibility
/// usually bypasses the app's undo.
@MainActor
struct ClipboardRelay {
    let pasteboard: any TextPasteboard
    let keys: any TextKeySender
    var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// How long to wait for an app to answer ⌘C.
    static let copyTimeout: Duration = .milliseconds(250)
    static let pollInterval: Duration = .milliseconds(10)
    /// How long the app gets to read a paste before the clipboard is put back.
    static let restoreDelay: Duration = .milliseconds(300)

    struct Copied: Equatable {
        var text: String
        var rich: RichText?
    }

    /// Presses ⌘C and reads what the app copied, then puts the clipboard back
    /// as it was. Nil when the app copied nothing in time (nothing selected,
    /// or no Copy), in which case the clipboard was never touched.
    func copySelection() async -> Copied? {
        let before = pasteboard.changeCount
        let saved = pasteboard.snapshot()
        keys.press(.copy)
        var waited: Duration = .zero
        while pasteboard.changeCount == before {
            guard waited < Self.copyTimeout else { return nil }
            await sleep(Self.pollInterval)
            waited += Self.pollInterval
        }
        let copied = pasteboard.string().map { Copied(text: $0, rich: pasteboard.richText()) }
        pasteboard.restore(saved)
        return copied
    }

    /// Pastes `text` over the selection, then restores the clipboard, unless
    /// something else has written to it in the meantime.
    func paste(_ text: String) async {
        let saved = pasteboard.snapshot()
        pasteboard.writeTransient(text)
        let ours = pasteboard.changeCount
        keys.press(.paste)
        await sleep(Self.restoreDelay)
        guard pasteboard.changeCount == ours else { return }
        pasteboard.restore(saved)
    }
}
