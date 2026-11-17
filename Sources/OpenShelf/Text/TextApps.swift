import AppKit

/// One way to find the text the user means.
enum TextReader: Equatable, Sendable {
    /// The focused element's selected text, through Accessibility.
    case accessibility
    /// ⌘C in the app, reading what it copied. Never used in terminals, where
    /// ⌘C can be mapped to Ctrl-C and would interrupt the running program.
    case copyShortcut
    /// What the user copied in the last minute (in a terminal, select then ⌘C).
    case recentClipboard
    /// GUI Emacs, asked through emacsclient for its region.
    case emacsClient
}

/// Where a result goes by default.
enum TextWriter: Equatable, Sendable {
    /// ⌘V over the selection, so the app's own ⌘Z undoes it.
    case paste
    /// Onto the clipboard only: in a terminal a paste can run as a command.
    case copyOnly
    /// GUI Emacs replaces its region itself, as one undoable change.
    case emacsClient
}

/// How the text wheel reads and writes in one app. All the per-app rules
/// live here; add an app by adding its bundle ID.
struct TextAppStrategy: Equatable, Sendable {
    var readers: [TextReader]
    var writer: TextWriter

    static let terminals: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty", "com.github.wez.wezterm",
        "org.alacritty", "io.alacritty", "net.kovidgoyal.kitty", "dev.warp.Warp-Stable",
    ]
    static let emacs: Set<String> = ["org.gnu.Emacs"]

    static let standard = TextAppStrategy(readers: [.accessibility, .copyShortcut], writer: .paste)
    static let terminal = TextAppStrategy(readers: [.accessibility, .recentClipboard], writer: .copyOnly)
    static let guiEmacs = TextAppStrategy(readers: [.emacsClient, .accessibility, .copyShortcut], writer: .emacsClient)

    static func `for`(bundleID: String?) -> TextAppStrategy {
        guard let bundleID else { return .standard }
        if terminals.contains(bundleID) { return .terminal }
        if emacs.contains(bundleID) { return .guiEmacs }
        return .standard
    }

    var isTerminal: Bool { writer == .copyOnly }

    /// The label under the wheel.
    var hint: String {
        isTerminal ? "Return copies · ⌃ pastes · ⇧ to shelf" : "Return replaces · ⌥ copies · ⇧ to shelf"
    }

    /// What to say when no route found any text.
    var nothingFoundHint: String {
        switch self {
        case .terminal: "Select text, ⌘C, then the shortcut"
        case .guiEmacs: "Select a region first"
        default: "Select text, or files in Finder"
        }
    }
}

/// Where a text tool's result goes, from the app and the keys held when it
/// was chosen. In a terminal the result is only copied, unless ⌃ asks for a
/// paste (for vim's insert mode, which only the user can know).
enum TextDelivery: Equatable {
    case replace
    case copy
    case shelf

    init(modifiers: NSEvent.ModifierFlags, strategy: TextAppStrategy = .standard) {
        if modifiers.contains(.shift) && !modifiers.contains(.option) {
            self = .shelf
        } else if strategy.isTerminal {
            self = modifiers.contains(.control) ? .replace : .copy
        } else {
            self = modifiers.contains(.option) ? .copy : .replace
        }
    }
}
