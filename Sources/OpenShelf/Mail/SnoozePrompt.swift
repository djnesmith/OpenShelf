import AppKit

/// The snooze prompt: a one-line field for a typed time, David's presets as buttons
/// (⌘1 to ⌘6), and the time it understood, shown before Return. Esc closes it.
@MainActor
final class SnoozePrompt: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = SnoozePrompt()

    private var panel: NSPanel?
    private let field = NSTextField()
    private let understood = NSTextField(labelWithString: "")
    private var onChoose: ((Date) -> Void)?
    private var onCancel: (() -> Void)?
    var calendar = Calendar.current
    var now: () -> Date = { .now }

    /// What the prompt would use now: the typed time, or nil when nothing is understood.
    var chosen: Date? { SnoozeTime.parse(field.stringValue, now: now(), calendar: calendar) }

    func show(onChoose: @escaping (Date) -> Void, onCancel: (() -> Void)? = nil) {
        let panel = prepare(onChoose: onChoose, onCancel: onCancel)
        panel.center()
        // A panel that takes the keyboard without making OpenShelf the active app: macOS
        // may refuse to activate an app from a key tap or hotkey, which left the field
        // without the cursor (David, 2026-11-20).
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// Builds and resets the prompt without putting it on screen (tests use this alone).
    @discardableResult
    func prepare(onChoose: @escaping (Date) -> Void, onCancel: (() -> Void)? = nil) -> NSPanel {
        self.onChoose = onChoose
        self.onCancel = onCancel
        let panel = self.panel ?? makePanel()
        field.stringValue = ""
        update()
        return panel
    }

    func close() {
        onChoose = nil
        onCancel = nil
        panel?.orderOut(nil)
    }

    /// The panel, for tests.
    var promptPanel: NSPanel? { panel }
    var promptField: NSTextField { field }
    var understoodText: String { understood.stringValue }

    func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Snooze until…"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onPreset = { [weak self] index in self?.choosePreset(index) }

        field.placeholderString = "5, 2h, 3d, 2w, fri 2pm, dec 3 9am"
        field.delegate = self
        understood.textColor = .secondaryLabelColor
        var rows: [NSView] = [field, understood]
        for index in SnoozeTime.presets.indices {
            let button = NSButton(title: "", target: self, action: #selector(presetButton(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.alignment = .left
            rows.append(button)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        field.widthAnchor.constraint(equalToConstant: 330).isActive = true
        panel.contentView = stack
        panel.initialFirstResponder = field
        self.panel = panel
        return panel
    }

    private var presetButtons: [NSButton] {
        (panel?.contentView?.subviews ?? []).compactMap { $0 as? NSButton }
    }

    private func update() {
        let date = chosen
        understood.stringValue = field.stringValue.isEmpty ? "Type a time, or pick one below" : date.map { "→ " + SnoozeTime.describe($0, calendar: calendar) } ?? "Not understood"
        for button in presetButtons {
            let preset = SnoozeTime.presets[button.tag]
            let when = SnoozeTime.describe(SnoozeTime.date(of: preset, now: now(), calendar: calendar), calendar: calendar)
            button.title = "⌘\(button.tag + 1)  \(preset.name.prefix(1).uppercased() + preset.name.dropFirst())   \(when)"
        }
    }

    func controlTextDidChange(_ notification: Notification) { update() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // Nothing understood: "Not understood" already says so; no sound.
            if let date = chosen { choose(date) }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            let onCancel = onCancel
            close()
            onCancel?()
            return true
        }
        return false
    }

    @objc private func presetButton(_ sender: NSButton) { choosePreset(sender.tag) }

    func choosePreset(_ index: Int) {
        guard SnoozeTime.presets.indices.contains(index) else { return }
        choose(SnoozeTime.date(of: SnoozeTime.presets[index], now: now(), calendar: calendar))
    }

    private func choose(_ date: Date) {
        let onChoose = onChoose
        close()
        onChoose?(date)
    }

    func windowWillClose(_ notification: Notification) { onChoose = nil }

    /// ⌘1 to ⌘6 choose a preset.
    private final class KeyPanel: NSPanel {
        var onPreset: (Int) -> Void = { _ in }
        override var canBecomeKey: Bool { true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...SnoozeTime.presets.count).contains(digit) {
                onPreset(digit - 1)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
