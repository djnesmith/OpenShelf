import AppKit
import Testing
@testable import OpenShelf

/// When the Edit window may paste over the selection it came from.
@MainActor
struct EditWriteBackTests {
    static func session(_ source: TextReader) -> SelectedTextController.Session {
        SelectedTextController.Session(
            text: "hello", rich: nil, app: NSRunningApplication.current, strategy: .standard, source: source,
            context: TextContext(text: "hello", hasRichText: false, canUndo: false), location: .zero
        )
    }

    @Test(arguments: [
        (TextReader.accessibility, SelectedTextRead.text("hello"), false, true),
        (.accessibility, .text("hello there"), false, false),
        // The field is gone, the selection collapsed, or a password field has focus.
        (.accessibility, .unavailable, false, false),
        (.accessibility, .nothingSelected, false, false),
        (.accessibility, .secure, false, false),
        (.accessibility, .notPermitted, false, false),
        // The app itself holding secure input refuses; one held elsewhere doesn't (the false rows).
        (.accessibility, .text("hello"), true, false),
        // Apps read with ⌘C can't be read back, so they paste as tools do, unless that app holds secure input.
        (.copyShortcut, .unavailable, false, true),
        (.copyShortcut, .unavailable, true, false),
        (.copyShortcut, .nothingSelected, false, false),
        // Copied text, with ⌃ held, pastes at the cursor: nothing is selected there.
        (.recentClipboard, .nothingSelected, false, true),
        (.recentClipboard, .unavailable, false, true),
        (.recentClipboard, .nothingSelected, true, false),
    ])
    func replacesOnlyAnUnchangedSelection(source: TextReader, now: SelectedTextRead, secure: Bool, expected: Bool) {
        #expect(SelectedTextController.canReplace(Self.session(source), now: now, appHoldsSecureInput: secure) == expected)
    }

    /// The other tools paste right after reading: an unreadable selection is
    /// trusted, but a password field that took focus meanwhile never gets the text.
    @Test(arguments: [
        (SelectedTextRead.text("hello"), true),
        (.text("other"), false),
        (.secure, false),
        (.unavailable, true),
        (.nothingSelected, true),
    ])
    func toolsNeverPasteIntoAPasswordField(now: SelectedTextRead, expected: Bool) {
        #expect(SelectedTextController.toolMayReplace(Self.session(.accessibility), now: now) == expected)
    }
}
