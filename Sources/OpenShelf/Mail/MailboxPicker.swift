import AppKit

/// The quick-filing picker: a field, the best matches below it, ↑ ↓ to choose, Return to
/// move, Esc to close.
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

    func show(mailboxes: [MailFiling.Mailbox], recent: [MailFiling.Mailbox], onChoose: @escaping (MailFiling.Mailbox) -> Void) {
        let panel = prepare(mailboxes: mailboxes, recent: recent, onChoose: onChoose)
        panel.center()
        // Takes the keyboard without activating OpenShelf, as the snooze prompt does: macOS
        // may refuse to activate an app from a key tap or hotkey.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// Builds and resets the picker without putting it on screen (tests use this alone).
    @discardableResult
    func prepare(mailboxes: [MailFiling.Mailbox], recent: [MailFiling.Mailbox], onChoose: @escaping (MailFiling.Mailbox) -> Void) -> NSPanel {
        self.mailboxes = mailboxes
        self.recent = recent
        self.onChoose = onChoose
        let panel = self.panel ?? makePanel()
        field.stringValue = ""
        update()
        return panel
    }

    var pickerField: NSTextField { field }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
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
        if field.stringValue.isEmpty { highlighted = 0 }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, box) in matches.enumerated() {
            let row = NSTextField(labelWithString: (index == highlighted ? "▸ " : "   ") + box.display)
            row.textColor = index == highlighted ? .labelColor : .secondaryLabelColor
            list.addArrangedSubview(row)
        }
        if matches.isEmpty { list.addArrangedSubview(NSTextField(labelWithString: "No mailbox matches")) }
    }

    func controlTextDidChange(_ notification: Notification) {
        highlighted = 0
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            highlighted = min(highlighted + 1, max(matches.count - 1, 0))
            update()
        case #selector(NSResponder.moveUp(_:)):
            highlighted = max(highlighted - 1, 0)
            update()
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

    func close() {
        onChoose = nil
        panel?.orderOut(nil)
    }
}
