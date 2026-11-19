import Foundation

/// What one reader found.
enum SelectedTextRead: Equatable {
    case text(String)
    /// A text field has focus but nothing is selected in it, as far as this reader can tell.
    case nothingSelected
    /// The focused field is a password field, or the app has secure input on.
    case secure
    /// Accessibility isn't allowed for OpenShelf yet (needed to read or to press ⌘C).
    case notPermitted
    /// This reader couldn't say (no focused element, no server, no recent copy).
    case unavailable
}

/// Where the wheel shortcut goes once shelves have had their turn: Finder's
/// files exactly as before, otherwise the frontmost app's text.
enum HotkeyRoute: Equatable {
    case finder
    /// Text, and the reader that found it.
    case text(String, from: TextReader)
    /// Ask macOS for Accessibility and say why.
    case askForAccessibility
    case secureInput
    /// No reader found text: a toast naming the app.
    case nothing

    static let finderBundleID = FinderSelection.finderBundleID

    /// Tries `strategy`'s readers in order. The first that finds text wins; a
    /// secure field stops everything. A reader that needs Accessibility and
    /// doesn't have it lets the others try, and Accessibility is asked for
    /// only when none of them found anything.
    @MainActor
    static func choose(
        frontmostBundleID: String?,
        appHoldsSecureInput: Bool,
        strategy: TextAppStrategy,
        read: (TextReader) async -> SelectedTextRead
    ) async -> HotkeyRoute {
        if frontmostBundleID == finderBundleID { return .finder }
        if appHoldsSecureInput { return .secureInput }
        var needsAccessibility = false
        for reader in strategy.readers {
            switch await read(reader) {
            case .text(let text) where !text.isEmpty: return .text(text, from: reader)
            case .secure: return .secureInput
            case .notPermitted: needsAccessibility = true
            case .text, .nothingSelected, .unavailable: continue
            }
        }
        return needsAccessibility ? .askForAccessibility : .nothing
    }

    /// Said when no reader found text in `appName`, with what to do instead.
    /// A terminal's selection may be there but unreadable (a TUI like herdr
    /// owns the mouse), so it says how to make it readable instead.
    static func nothingSelectedToast(appName: String?, strategy: TextAppStrategy, shortcut: KeyCombo?) -> Toast {
        if strategy.isTerminal {
            return Toast(
                systemImage: "text.cursor",
                title: "Copy first: ⌘C, then \(shortcut?.displayString ?? "the shortcut")",
                subtitle: strategy.nothingFoundHint
            )
        }
        return Toast(
            systemImage: "text.cursor",
            title: "No selected text found in \(appName ?? "this app")",
            subtitle: [strategy.nothingFoundHint, shortcut.map { "\($0.displayString) twice for Settings" }]
                .compactMap { $0 }.joined(separator: " · ")
        )
    }
}
