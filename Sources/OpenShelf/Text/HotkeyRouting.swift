import Foundation

/// What reading the frontmost app's selection found.
enum SelectedTextRead: Equatable {
    /// Selected text, with the app it came from.
    case text(String)
    /// A text field has focus but nothing is selected in it.
    case nothingSelected
    /// The focused field is a password field, or secure input is on.
    case secure
    /// Accessibility isn't allowed for OpenShelf yet.
    case notPermitted
    /// The app didn't say (no focused element, or it doesn't support the
    /// selected-text attribute); worth trying ⌘C.
    case unavailable
}

/// Where the wheel shortcut goes once shelves have had their turn: Finder's
/// files exactly as before, otherwise the frontmost app's selected text.
enum HotkeyRoute: Equatable {
    case finder
    case text(String)
    /// Ask macOS for Accessibility and say why.
    case askForAccessibility
    case secureInput
    /// Nothing to open a wheel for: the "select something first" toast.
    case nothing

    static let finderBundleID = FinderSelection.finderBundleID

    /// - Parameters:
    ///   - read: Reads the selection with Accessibility; only called when Finder isn't in front.
    ///   - copy: The ⌘C fallback, only called when Accessibility couldn't say.
    @MainActor
    static func choose(
        frontmostBundleID: String?,
        isSecureInputOn: Bool,
        read: () -> SelectedTextRead,
        copy: () async -> String?
    ) async -> HotkeyRoute {
        if frontmostBundleID == finderBundleID { return .finder }
        if isSecureInputOn { return .secureInput }
        switch read() {
        case .text(let text): return text.isEmpty ? .nothing : .text(text)
        case .nothingSelected: return .nothing
        case .secure: return .secureInput
        case .notPermitted: return .askForAccessibility
        case .unavailable:
            guard let copied = await copy(), !copied.isEmpty else { return .nothing }
            return .text(copied)
        }
    }
}
