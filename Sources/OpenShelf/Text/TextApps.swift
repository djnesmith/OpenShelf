import AppKit

/// One way to find the text the user means.
enum TextReader: Equatable, Sendable {
    /// The focused element's selected text, through Accessibility.
    case accessibility
    /// ⌘C in the app, reading what it copied. Never used in terminals, where
    /// ⌘C can be mapped to Ctrl-C and would interrupt the running program.
    case copyShortcut
    /// The clipboard's text, however old: the last way in when nothing is
    /// selected, in every app (a terminal's selection is often unreadable).
    /// The result is only copied, since there is no selection to put it over.
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

    // A selection always comes before the clipboard: recentClipboard is last.
    static let standard = TextAppStrategy(readers: [.accessibility, .copyShortcut, .recentClipboard], writer: .paste)
    static let terminal = TextAppStrategy(readers: [.accessibility, .recentClipboard], writer: .copyOnly)
    static let guiEmacs = TextAppStrategy(readers: [.emacsClient, .accessibility, .copyShortcut, .recentClipboard], writer: .emacsClient)

    static func `for`(bundleID: String?) -> TextAppStrategy {
        guard let bundleID else { return .standard }
        if terminals.contains(bundleID) { return .terminal }
        if emacs.contains(bundleID) { return .guiEmacs }
        return .standard
    }

    var isTerminal: Bool { writer == .copyOnly }

    /// Whether a result for text found by `source` is only copied: always in
    /// a terminal, and for copied text anywhere, as nothing is selected.
    func isCopyOnly(from source: TextReader) -> Bool {
        isTerminal || source == .recentClipboard
    }

    /// The label under the wheel for text found by `source`.
    func hint(for source: TextReader) -> String {
        isCopyOnly(from: source) ? "Return copies · ⌃ pastes · ⇧ to shelf" : "Return replaces · ⌥ copies · ⇧ to shelf"
    }

    /// What to say when no route found any text.
    var nothingFoundHint: String {
        switch self {
        case .terminal: "OpenShelf can't see a terminal's selection, and the clipboard has no text"
        case .guiEmacs: "No region, and the clipboard has no text"
        default: "Nothing selected, and the clipboard has no text"
        }
    }
}

/// Where a text tool's result goes, from the app, where the text came from
/// and the keys held when it was chosen. In a terminal, and for copied text
/// with nothing selected, the result is only copied, unless ⌃ asks for a
/// paste (vim's insert mode, or the cursor's place in a text field).
enum TextDelivery: Equatable {
    case replace
    case copy
    case shelf

    /// `editable` is whether the selection can be changed where it is: false for text on
    /// a web page, a PDF or a message being read, nil when Accessibility can't tell (then
    /// it is pasted over, as before). A selection that can't be changed goes on the
    /// clipboard (David, 2026-11-20).
    init(modifiers: NSEvent.ModifierFlags, strategy: TextAppStrategy = .standard, source: TextReader = .accessibility, editable: Bool? = nil) {
        if modifiers.contains(.shift) && !modifiers.contains(.option) {
            self = .shelf
        } else if strategy.isCopyOnly(from: source) {
            self = modifiers.contains(.control) ? .replace : .copy
        } else if editable == false {
            self = .copy
        } else {
            self = modifiers.contains(.option) ? .copy : .replace
        }
    }
}
