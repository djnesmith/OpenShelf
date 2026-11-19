import AppKit
import ApplicationServices

/// The single-key layer's key tap (MAIL-PLAN slice E). Off by default; installed only
/// while the setting is on and Mail is in front, removed as soon as Mail isn't. It takes
/// a key only when MailKeys says so and passes everything else to Mail untouched; it
/// never records or logs keys. While installed, a menu bar item says "Mail keys".
@MainActor
final class MailKeyTap {
    static let shared = MailKeyTap()
    static let enabledKey = "MailSingleKeys"

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var indicator: NSStatusItem?
    private var pending: Character?
    private var pendingSince = Date.distantPast

    var isInstalled: Bool { tap != nil }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Installs or removes the tap for the app now in front.
    func update(front bundleID: String?) {
        if Self.isEnabled, bundleID == MailMenu.bundleID { install() } else { remove() }
    }

    private func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
            // The tap runs on the main run loop; only the yes/no answer crosses over.
            nonisolated(unsafe) let event = event
            let takes = MainActor.assumeIsolated { MailKeyTap.shared.takes(type: type, event: event) }
            return takes ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil) else {
            ToastController.shared.show(Toast(systemImage: "keyboard", title: "Mail keys are off", subtitle: "macOS didn't allow the key tap (Accessibility)"), for: .seconds(4))
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Mail keys"
        item.button?.font = .systemFont(ofSize: 11, weight: .medium)
        item.button?.toolTip = "OpenShelf's single keys are on while Mail is in front; ? lists them"
        indicator = item
    }

    func remove() {
        pending = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if let indicator { NSStatusBar.system.removeStatusItem(indicator) }
        indicator = nil
        MailKeyHelp.shared.close()
    }

    /// Whether the tap takes this key from Mail. False (the key goes to Mail) whenever in doubt.
    private func takes(type: CGEventType, event: CGEvent) -> Bool {
        // macOS turns a slow tap off; it is turned back on, and the key passes.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, let key = Self.character(of: event) else { return false }
        if MailKeyHelp.shared.isOpen {
            MailKeyHelp.shared.close()
            return true
        }
        if Date().timeIntervalSince(pendingSince) > MailKeys.prefixTimeout { pending = nil }
        let outcome = MailKeys.outcome(for: key, pending: pending)
        pending = nil
        guard outcome != .pass, Self.focusAllows(event: event) else { return false }
        switch outcome {
        case .pass:
            return false
        case .prefix(let prefix):
            pending = prefix
            pendingSince = Date()
            return true
        case .act(let action):
            // After the tap returns, so the key is gone before Mail's menu is used.
            DispatchQueue.main.async { MainActor.assumeIsolated { MailKeyActions.perform(action) } }
            return true
        }
    }

    private static func character(of event: CGEvent) -> Character? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length == 1 else { return nil }
        return String(utf16CodeUnits: chars, count: 1).first
    }

    /// Mail's focus, read with a short timeout; anything unreadable lets the key through.
    private static func focusAllows(event: CGEvent) -> Bool {
        let flags = event.flags
        var modifiers: MailKeys.Modifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]).isEmpty { modifiers.insert(.other) }
        guard let mail = MailMenu.running else { return false }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return false }
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXEditable" as CFString, &editable)
        let role = AXMenuNode.string(focused, kAXRoleAttribute)
        // Only a web area is ambiguous (a message read, or one being written), so only then
        // is Mail's menu asked whether Send is enabled; an unanswered question counts as yes.
        let sendEnabled = role == "AXWebArea" ? (MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }?.isEnabled ?? true) : false
        return MailKeys.mayTake(
            focusedRole: role,
            isEditable: (editable as? Bool) ?? false,
            sendEnabled: sendEnabled,
            modifiers: modifiers
        )
    }
}

/// What a single key does in Mail.
@MainActor
enum MailKeyActions {
    static func perform(_ action: MailKeys.Action) {
        switch action {
        case .menu(let top, let title):
            press(title, under: top)
        case .favorite(let name):
            press(name, under: "Mailbox", within: "Go to Favorite Mailbox")
        case .nextMessage:
            moveSelection(by: 1)
        case .previousMessage:
            moveSelection(by: -1)
        case .archiveThenPrevious:
            press("Archive", under: "Message")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { moveSelection(by: -1) } }
        case .snooze:
            MailHelpers.shared.showPrompt()
        case .file:
            MailFiling.showPicker()
        case .showKeys:
            MailKeyHelp.shared.show()
        }
    }

    /// Presses the enabled item titled `title` anywhere under the menu bar's `top` menu
    /// (and under its `within` submenu when given). Nothing happens if there's none.
    static func press(_ title: String, under top: String, within submenu: String? = nil) {
        guard let bar = MailMenu.menuBar(), let item = item(title, under: top, within: submenu, in: bar), item.isEnabled else { return }
        _ = item.press()
    }

    /// The item titled `title` anywhere under the menu bar's `top` menu, and under its
    /// `within` submenu when given.
    static func item(_ title: String, under top: String, within submenu: String? = nil, in bar: [MenuNode]) -> MenuNode? {
        guard var menu = bar.first(where: { $0.title == top }) else { return nil }
        if let submenu {
            guard let inner = MailMenu.findAnywhere(submenu, in: menu.children) else { return nil }
            menu = inner
        }
        return MailMenu.findAnywhere(title, in: menu.children)
    }

    /// j and k: the message list's selection moves one row, through Accessibility.
    static func moveSelection(by step: Int) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard var list = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return }
        // A focused row or cell belongs to the list above it.
        while let role = AXMenuNode.string(list, kAXRoleAttribute), !["AXTable", "AXOutline"].contains(role) {
            guard let parent = AXMenuNode.element(list, kAXParentAttribute) else { return }
            list = parent
        }
        var rowsValue: CFTypeRef?
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXRowsAttribute as CFString, &rowsValue) == .success,
              let rows = rowsValue as? [AXUIElement], !rows.isEmpty else { return }
        AXUIElementCopyAttributeValue(list, kAXSelectedRowsAttribute as CFString, &selectedValue)
        let selected = (selectedValue as? [AXUIElement]) ?? []
        let current = selected.first.flatMap { row in rows.firstIndex { CFEqual($0, row) } }
        let target = MailKeys.row(after: current, by: step, count: rows.count)
        AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, [rows[target]] as CFArray)
    }
}

extension MailKeys {
    /// The row j or k lands on: one further, stopping at the ends; the first row when
    /// none is selected.
    static func row(after current: Int?, by step: Int, count: Int) -> Int {
        guard let current else { return 0 }
        return min(max(current + step, 0), count - 1)
    }
}

extension MailMenu {
    /// The first item titled `title` anywhere under `items`, depth first.
    static func findAnywhere(_ title: String, in items: [MenuNode]) -> MenuNode? {
        for item in items {
            if item.title == title { return item }
            if let found = findAnywhere(title, in: item.children) { return found }
        }
        return nil
    }
}

/// The `?` list: a small panel that never takes focus from Mail; any key closes it.
@MainActor
final class MailKeyHelp {
    static let shared = MailKeyHelp()
    private var panel: NSPanel?
    var isOpen: Bool { panel?.isVisible == true }

    func show() {
        let panel = self.panel ?? make()
        panel.center()
        panel.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Mail keys"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let text = MailKeys.help.map { "\($0.0.padding(toLength: 24, withPad: " ", startingAt: 0))\($0.1)" }.joined(separator: "\n")
        let label = NSTextField(labelWithString: text + "\n\nAny key closes this.")
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        panel.contentView = stack
        self.panel = panel
        return panel
    }
}
