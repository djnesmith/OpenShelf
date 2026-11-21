import AppKit

/// The quick-filing picker: a field, the best matches below it, ↑ ↓ (or ⌃N ⌃P) to choose,
/// Return to move, Esc to close.
@MainActor
final class MailboxPicker: NSObject, NSTextFieldDelegate {
    static let shared = MailboxPicker()

    private var panel: NSPanel?
    private let field = NSTextField()
    private let list = NSStackView()
    private var mailboxes: [MailFiling.Mailbox] = []
    private var recent: [MailFiling.Mailbox] = []
    private(set) var matches: [MailFiling.Mailbox] = []
    private(set) var highlighted = 0
    private var onChoose: ((MailFiling.Mailbox) -> Void)?

    /// Whether Mail's mailboxes are still being listed (the picker says so until they come).
    private(set) var loading = false
    var isOpen: Bool { panel?.isVisible == true && onChoose != nil }

    func show(mailboxes: [MailFiling.Mailbox], recent: [MailFiling.Mailbox], loading: Bool = false, onChoose: @escaping (MailFiling.Mailbox) -> Void) {
        let panel = prepare(mailboxes: mailboxes, recent: recent, loading: loading, onChoose: onChoose)
        panel.center()
        // Takes the keyboard without activating OpenShelf, as the snooze prompt does: macOS
        // may refuse to activate an app from a key tap or hotkey.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// Builds and resets the picker without putting it on screen (tests use this alone).
    @discardableResult
    func prepare(mailboxes: [MailFiling.Mailbox], recent: [MailFiling.Mailbox], loading: Bool = false, onChoose: @escaping (MailFiling.Mailbox) -> Void) -> NSPanel {
        self.loading = loading
        self.mailboxes = mailboxes
        self.recent = recent
        self.onChoose = onChoose
        let panel = self.panel ?? makePanel()
        field.stringValue = ""
        highlighted = 0
        update()
        return panel
    }

    var pickerField: NSTextField { field }

    /// Mail's list has arrived: the picker shows it, keeping what was typed.
    func update(mailboxes: [MailFiling.Mailbox]) {
        self.mailboxes = mailboxes
        loading = false
        update()
    }

    /// The text of the list's rows, for tests.
    var rowTexts: [String] { list.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue } }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.onStep = { [weak self] in self?.move(by: $0) }
        panel.title = "Move to…"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        field.placeholderString = "Type part of a mailbox name"
        field.delegate = self
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 3
        let stack = NSStackView(views: [field, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        field.widthAnchor.constraint(equalToConstant: 350).isActive = true
        panel.contentView = stack
        panel.initialFirstResponder = field
        self.panel = panel
        return panel
    }

    private func update() {
        matches = MailFiling.rank(field.stringValue, in: mailboxes, recent: recent)
        highlighted = min(highlighted, max(matches.count - 1, 0))
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, box) in matches.enumerated() {
            let row = NSTextField(labelWithString: (index == highlighted ? "▸ " : "   ") + box.display)
            row.textColor = index == highlighted ? .labelColor : .secondaryLabelColor
            list.addArrangedSubview(row)
        }
        if matches.isEmpty { list.addArrangedSubview(NSTextField(labelWithString: loading ? "Listing mailboxes…" : "No mailbox matches")) }
    }

    func controlTextDidChange(_ notification: Notification) {
        highlighted = 0
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            guard matches.indices.contains(highlighted) else { return true }
            let chosen = matches[highlighted]
            let onChoose = onChoose
            close()
            onChoose?(chosen)
        case #selector(NSResponder.cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }

    /// Moves the highlight one row, stopping at the first and last rows.
    func move(by step: Int) {
        highlighted = min(max(highlighted + step, 0), max(matches.count - 1, 0))
        update()
    }

    func close() {
        onChoose = nil
        panel?.orderOut(nil)
    }

    /// ⌃N down, ⌃P up; nil for any other key. Read from the key itself, not from the
    /// user's key bindings, so it works whatever DefaultKeyBinding.dict says.
    nonisolated static func step(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .control else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n": return 1
        case "p": return -1
        default: return nil
        }
    }

    /// Takes ⌃N and ⌃P before the field does, so neither types into it.
    final class KeyPanel: NSPanel {
        var onStep: (Int) -> Void = { _ in }
        override func sendEvent(_ event: NSEvent) {
            if let step = MailboxPicker.step(for: event) {
                onStep(step)
                return
            }
            super.sendEvent(event)
        }
    }
}
