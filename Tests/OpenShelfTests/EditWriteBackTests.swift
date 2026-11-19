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
        (TextReader.accessibility, SelectedTextRead.text("hello"), true),
        (.accessibility, .text("hello there"), false),
        // The field is gone, the selection collapsed, or a password field has focus.
        (.accessibility, .unavailable, false),
        (.accessibility, .nothingSelected, false),
        (.accessibility, .secure, false),
        (.accessibility, .notPermitted, false),
        // Apps read with ⌘C can't be read back, so they paste as tools do.
        (.copyShortcut, .unavailable, true),
        (.copyShortcut, .nothingSelected, false),
        // Copied text, with ⌃ held, pastes at the cursor: nothing is selected
        // there, but never into a password field.
        (.recentClipboard, .nothingSelected, true),
        (.recentClipboard, .unavailable, true),
        (.recentClipboard, .secure, false),
    ])
    func replacesOnlyAnUnchangedSelection(source: TextReader, now: SelectedTextRead, expected: Bool) {
        #expect(SelectedTextController.canReplace(Self.session(source), now: now) == expected)
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

    /// A password field (browser, 1Password, Passwords) that has focus at paste
    /// time never gets the text, from Edit or from a tool.
    @Test(arguments: [TextReader.accessibility, .copyShortcut, .recentClipboard])
    func noPasteIntoAPasswordField(source: TextReader) {
        #expect(!SelectedTextController.canReplace(Self.session(source), now: .secure))
        #expect(!SelectedTextController.toolMayReplace(Self.session(source), now: .secure))
    }
}
