import AppKit
import ApplicationServices

/// The single-key layer's key tap (MAIL-PLAN slice E). Off by default; installed only
/// while the setting is on and Mail is in front, removed as soon as Mail isn't. It takes
/// a key only when MailKeys says so and passes everything else to Mail untouched; it
/// never records or logs keys. No menu bar item (David, 2026-11-20: "i don't want any menu bar
/// item for it"); the checkmark on Mail Single Keys in OpenShelf's menu is the only sign.
@MainActor
final class MailKeyTap {
    static let shared = MailKeyTap()
    static let enabledKey = "MailSingleKeys"

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
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
    }

    func remove() {
        pending = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        MailKeyHelp.shared.close()
    }

    /// Whether the tap takes this key from Mail. False (the key goes to Mail) whenever in doubt.
    /// `ownPanelHasKeyboard` and `focusAllows` are parameters for tests.
    func takes(type: CGEventType, event: CGEvent, ownPanelHasKeyboard: Bool = NSApp.keyWindow != nil,
               focusAllows: @MainActor (CGEvent, MailKeys.Outcome) -> Bool = MailKeyTap.focusAllows) -> Bool {
        // macOS turns a slow tap off; it is turned back on, and the key passes.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, let key = Self.character(of: event) else { return false }
        // One action per key down: a held Esc or u repeats, and after a close the next window
        // in front would get it (2026-11-20). Repeats right after a close are dropped.
        if key == MailKeys.escape || key == "u", event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Date().timeIntervalSince(MailKeyActions.lastCloseAt) < 2
        }
        // One of OpenShelf's own panels (the snooze prompt, the folder picker) has the
        // keyboard over Mail: every key is typed there.
        if ownPanelHasKeyboard, !MailKeyHelp.shared.isOpen { return false }
        if MailKeyHelp.shared.isOpen {
            MailKeyHelp.shared.close()
            return true
        }
        if Date().timeIntervalSince(pendingSince) > MailKeys.prefixTimeout { pending = nil }
        if key == MailKeys.escape, pending == nil, !ownPanelHasKeyboard, let window = closesMessageWindow(event) {
            // After the tap returns, so the key is gone before the window is closed.
            DispatchQueue.main.async { MainActor.assumeIsolated { MailKeyActions.close(window) } }
            return true
        }
        let outcome = MailKeys.outcome(for: key, pending: pending)
        pending = nil
        guard outcome != .pass, focusAllows(event, outcome) else { return false }
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
    static func focusAllows(_ event: CGEvent, _ outcome: MailKeys.Outcome) -> Bool {
        let flags = event.flags
        var modifiers: MailKeys.Modifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]).isEmpty { modifiers.insert(.other) }
        guard let mail = MailMenu.running else { return false }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return false }
        if character(of: event) == MailKeys.escape {
            let list = AXSelectableList(focused: focused)
            return MailKeys.mayTakeEscape(
                focusedRole: AXMenuNode.string(focused, kAXRoleAttribute),
                selectedCount: list?.selectedRows.count ?? 0,
                hasSheetOrPopover: hasSheetOrPopover(app),
                modifiers: modifiers,
                mailHasFocus: MailMenu.hasKeyboardFocus()
            )
        }
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXEditable" as CFString, &editable)
        let role = AXMenuNode.string(focused, kAXRoleAttribute)
        // Only a web area is ambiguous (a message read, or one being written), so only then
        // is Mail's menu asked whether Send is enabled; an unanswered question counts as yes.
        let inViewer = !MailKeys.listRoles.contains(role ?? "") && role != "AXWebArea" && isInMessageViewer(focused)
        let inWindow = !isInMessageViewer(focused) && isMessageWindow(app)
        // Mail has no Send item outside a message being written (Check Mail, 2026-11-20: "not
        // found" in the viewer and in a message window), so a missing one is off; only menus
        // that can't be read at all count as on.
        let sendEnabled = role == "AXWebArea" || inViewer || inWindow ? MailKeys.sendIsOn(menuRead: MailMenu.menuBar() != nil,
            send: MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }?.isEnabled) : false
        let action: MailKeys.Action? = if case .act(let action) = outcome { action } else { nil }
        let isEditable = (editable as? Bool) ?? false
        let taken = MailKeys.mayTake(
            focusedRole: role,
            isEditable: isEditable,
            sendEnabled: sendEnabled,
            modifiers: modifiers,
            mailHasFocus: MailMenu.hasKeyboardFocus(),
            // A prefix (g, *) has no action yet, so it is taken only in the list.
            inMessageViewer: inViewer,
            inMessageWindow: inWindow,
            action: action
        )
        // Outside the list, in the viewer or a message window and nothing editable: why.
        if (inViewer || inWindow || role == "AXWebArea"), !isEditable, !sendEnabled, let name = character(of: event) {
            let place = inWindow ? "message window" : (inViewer ? "viewer, not the list" : "web area")
            KeysLog.note("key \(name) in \(place) (\(role ?? "?")): \(taken ? "taken" : "passed, not a key for one message here")")
        } else if inViewer || inWindow, let name = character(of: event) {
            KeysLog.note("key \(name): passed, \(isEditable ? "editable focus" : "Send is on")")
        }
        return taken
    }

    /// Whether `element` is inside Mail's viewer window (identifier
    /// "Mail.messageViewer.window…", from David's Check Mail on 2026-11-20), not a window
    /// of its own such as a message being written.
    static func isInMessageViewer(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<30 {
            guard let node = current else { return false }
            if AXMenuNode.string(node, kAXRoleAttribute) == kAXWindowRole {
                return MailKeys.isMainViewer(AXDialogNode(element: node))
            }
            current = AXMenuNode.element(node, kAXParentAttribute)
        }
        return false
    }
}

extension MailKeyTap {
    /// Whether Mail's front window is a message open on its own (not the viewer, not one
    /// being written), as the Esc rule reads it.
    static func isMessageWindow(_ app: AXUIElement) -> Bool {
        guard let window = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return false }
        let facts = facts(window, app: app)
        return MailKeys.mayCloseWithEscape(facts, focusedRole: nil, isEditable: false, sendEnabled: false, modifiers: [], mailHasFocus: true)
    }

    /// Mail's front window when Esc should close it (a message open on its own), or nil.
    func closesMessageWindow(_ event: CGEvent) -> AXUIElement? {
        guard let mail = MailMenu.running else { return nil }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let window = AXMenuNode.element(app, kAXFocusedWindowAttribute),
              let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return nil }
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXEditable" as CFString, &editable)
        let sendEnabled = MailKeys.sendIsOn(menuRead: MailMenu.menuBar() != nil, send: MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }?.isEnabled)
        let facts = Self.facts(window, app: app)
        let allowed = MailKeys.mayCloseWithEscape(
            facts, focusedRole: AXMenuNode.string(focused, kAXRoleAttribute), isEditable: (editable as? Bool) ?? false,
            sendEnabled: sendEnabled, modifiers: event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty ? [] : .other,
            mailHasFocus: MailMenu.hasKeyboardFocus()
        )
        if !facts.isViewer, !facts.hasComposeControls {
            KeysLog.note("Esc in a non-viewer window: \(allowed ? "closing" : "passed") (sheet/popover \(facts.hasSheetOrPopover), text fields \(facts.textFieldCount), Send on \(sendEnabled), standard \(facts.isStandardWindow))")
        }
        return allowed ? window : nil
    }

    /// The front window's facts for the Esc rule, read a few levels deep (no text).
    static func facts(_ window: AXUIElement, app: AXUIElement) -> MailKeys.WindowFacts {
        var composeControls = false, textFields = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 4, !composeControls else { return }
            for child in AXMenuNode.childElements(element) {
                let role = AXMenuNode.string(child, kAXRoleAttribute) ?? ""
                let id = AXMenuNode.string(child, kAXIdentifierAttribute) ?? ""
                if ["send", "popup_from", "sendLater"].contains(id) { composeControls = true; return }
                if role == kAXTextFieldRole && depth == 0 { textFields += 1 }
                if !["AXWebArea", "AXScrollArea", "AXTable", "AXOutline"].contains(role) { walk(child, depth: depth + 1) }
            }
        }
        walk(window, depth: 0)
        return MailKeys.WindowFacts(
            isStandardWindow: AXMenuNode.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
            isViewer: MailKeys.isMainViewer(AXDialogNode(element: window)),
            hasSheetOrPopover: hasSheetOrPopover(app),
            hasComposeControls: composeControls,
            textFieldCount: textFields
        )
    }

    /// A sheet on Mail's front window, or a popover anywhere in Mail. Unreadable counts
    /// as yes, so Esc goes to Mail.
    static func hasSheetOrPopover(_ app: AXUIElement) -> Bool {
        guard let front = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return true }
        if AXMenuNode.childElements(front).contains(where: { ["AXSheet", "AXPopover"].contains(AXMenuNode.string($0, kAXRoleAttribute) ?? "") }) { return true }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return true }
        return windows.contains { window in
            AXMenuNode.string(window, kAXRoleAttribute) == "AXPopover"
                || AXMenuNode.childElements(window).contains { AXMenuNode.string($0, kAXRoleAttribute) == "AXPopover" }
        }
    }
}

/// Mail's message list through Accessibility: the table or outline above the focused
/// element, its rows and its selected rows.
@MainActor
struct AXSelectableList: MailKeys.SelectableList {
    let list: AXUIElement
    let rows: [AXUIElement]
    let focused: AXUIElement

    init?(focused: AXUIElement) {
        var list = focused
        while let role = AXMenuNode.string(list, kAXRoleAttribute), !["AXTable", "AXOutline"].contains(role) {
            guard let parent = AXMenuNode.element(list, kAXParentAttribute) else { return nil }
            list = parent
        }
        var rowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXRowsAttribute as CFString, &rowsValue) == .success,
              let rows = rowsValue as? [AXUIElement] else { return nil }
        self.list = list
        self.rows = rows
        self.focused = focused
    }

    init(list: AXUIElement, rows: [AXUIElement]) {
        self.list = list
        self.rows = rows
        self.focused = list
    }

    /// The message list of Mail's viewer window (MailKeys.messageList).
    static func inViewer(_ window: AXUIElement) -> AXSelectableList? {
        guard let node = MailKeys.messageList(in: AXDialogNode(element: window)) as? AXDialogNode else { return nil }
        var rowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node.element, kAXRowsAttribute as CFString, &rowsValue) == .success,
              let rows = rowsValue as? [AXUIElement] else { return nil }
        return AXSelectableList(list: node.element, rows: rows)
    }

    var selectedRows: [Int] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXSelectedRowsAttribute as CFString, &value)
        return ((value as? [AXUIElement]) ?? []).compactMap { row in rows.firstIndex { CFEqual($0, row) } }
    }

    var focusedRow: Int? {
        var element: AXUIElement? = focused
        // A focused cell belongs to the row above it.
        while let current = element, AXMenuNode.string(current, kAXRoleAttribute) != kAXRowRole {
            element = AXMenuNode.element(current, kAXParentAttribute)
            if element.map({ CFEqual($0, list) }) == true { return nil }
        }
        return element.flatMap { row in rows.firstIndex { CFEqual($0, row) } }
    }

    func select(_ indices: [Int]) -> Bool {
        AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, indices.map { rows[$0] } as CFArray) == .success
    }
}

/// What a single key does in Mail.
@MainActor
enum MailKeyActions {
    static func perform(_ action: MailKeys.Action) {
        switch action {
        case .menu("Message", "Open Message"):
            openAndBind()
        case .menu("Message", "Archive"), .menu("Edit", "Delete"):
            guard case .menu(let top, let title) = action else { return }
            if !conversationAction(archive: title == "Archive") { press(title, under: top) }
        case .menu(let top, let title):
            press(title, under: top)
        case .favorite(let name):
            press(name, under: "Mailbox", within: "Go to Favorite Mailbox")
        case .nextMessage:
            moveSelection(by: 1)
        case .previousMessage:
            moveSelection(by: -1)
        case .archiveThenPrevious:
            if conversationAction(archive: true) { return }
            press("Archive", under: "Message")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { moveSelection(by: -1) } }
        case .snooze:
            MailHelpers.shared.showPrompt()
        case .file:
            MailFiling.showPicker()
        case .showKeys:
            MailKeyHelp.shared.show()
        case .clearSelection:
            clearSelection()
        case .backToList:
            backToList()
        case .firstMessage:
            selectEnd(last: false)
        case .lastMessage:
            selectEnd(last: true)
        }
    }

    /// Presses the enabled item titled `title` anywhere under the menu bar's `top` menu
    /// (and under its `within` submenu when given). Nothing happens if there's none.
    /// Presses Mail's menu item; when it isn't there or is off, a short toast and a keys.log
    /// line say so, so a single key never fails silently (2026-11-20: `o` did nothing).
    @discardableResult
    static func press(_ title: String, under top: String, within submenu: String? = nil) -> Bool {
        guard let bar = MailMenu.menuBar() else { return notPressed(title, "Mail's menus can't be read") }
        guard let item = item(title, under: top, within: submenu, in: bar) else { return notPressed(title, "no “\(title)” in Mail's \(top) menu") }
        guard item.isEnabled else { return notPressed(title, "“\(title)” is off here") }
        return item.press() || notPressed(title, "“\(title)” didn't respond")
    }

    /// Presses Mail's item titled `title` in whichever top menu has it.
    @discardableResult
    static func pressAnywhere(_ title: String) -> Bool {
        guard let bar = MailMenu.menuBar() else { return notPressed(title, "Mail's menus can't be read") }
        guard let item = MailMenu.findAnywhere(title, in: bar) else { return notPressed(title, "no “\(title)” in Mail's menus") }
        guard item.isEnabled else { return notPressed(title, "“\(title)” is off here") }
        return item.press() || notPressed(title, "“\(title)” didn't respond")
    }

    private static func notPressed(_ title: String, _ reason: String) -> Bool {
        KeysLog.note("menu \(title): not pressed, \(reason)")
        ToastController.shared.show(Toast(systemImage: "keyboard", title: "Mail key did nothing", subtitle: reason), for: .seconds(3))
        return false
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

    /// `e` or `x` in a message window: what Archive or Delete does with that message's row
    /// selected in the list. False when the front window isn't a message window (the caller
    /// then presses the menu item as usual).
    static func conversationAction(archive: Bool, scripting: MailScripting = AppleScriptMail()) -> Bool {
        guard let mail = MailMenu.running else { return false }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard MailKeyTap.isMessageWindow(app), let window = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return false }
        var windowsValue: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        let viewer = ((windowsValue as? [AXUIElement]) ?? []).first {
            AXMenuNode.string($0, kAXIdentifierAttribute)?.hasPrefix("Mail.messageViewer.window") == true
        }
        let list = viewer.flatMap(AXSelectableList.inViewer)
        let current = Set(scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
        let plan = MailKeys.conversationPlan(bound: MailWindowBindings.ids(for: window), selectedRows: list?.selectedRows.count ?? 0, current: current)
        let verb = archive ? "Archived" : "Trashed"
        switch plan {
        case .viaList(let count):
            close(window)
            if let viewer { AXUIElementPerformAction(viewer, kAXRaiseAction as CFString) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    press(archive ? "Archive" : "Delete", under: archive ? "Message" : "Edit")
                    ToastController.shared.show(Toast(systemImage: archive ? "archivebox" : "trash", title: "\(verb) the conversation",
                                                      subtitle: "As from the list: \(count) message\(count == 1 ? "" : "s") selected there"), for: MailHelpers.successToast)
                }
            }
        case .thisMessage:
            press(archive ? "Archive" : "Delete", under: archive ? "Message" : "Edit")
            ToastController.shared.show(Toast(systemImage: archive ? "archivebox" : "trash", title: "\(verb) 1 message",
                                              subtitle: "Conversation not confirmed, so only this one"), for: .seconds(4))
        }
        return true
    }

    /// `o`: opens the selected message, and remembers which Message-IDs were selected for
    /// the window it opens, so `e` and `x` there can tell the list still holds that row.
    static func openAndBind(scripting: MailScripting = AppleScriptMail()) {
        let ids = Set(scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
        // Mail's "Open Message" (MainMenu.loctable 1772) is looked for in every menu.
        guard pressAnywhere("Open Message") else { return }
        guard !ids.isEmpty, let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if let window = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeyTap.isMessageWindow(app) {
                    MailWindowBindings.bind(window, ids: ids)
                    return
                }
            }
        }
    }

    /// `u`: a message open in its own window closes, as Esc does; in the viewer the keyboard
    /// goes back to the message list, on the selected message (the selection is unchanged).
    static func backToList() {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let window = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return }
        let facts = MailKeyTap.facts(window, app: app)
        let focusInList = AXMenuNode.element(app, kAXFocusedUIElementAttribute).flatMap { AXMenuNode.string($0, kAXRoleAttribute) }.map(MailKeys.listRoles.contains) ?? false
        let sendEnabled = MailKeys.sendIsOn(menuRead: MailMenu.menuBar() != nil, send: MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }?.isEnabled)
        switch MailKeys.backToList(facts, focusInList: focusInList, sendEnabled: sendEnabled) {
        case .close: close(window)
        case .focusList:
            if let list = AXSelectableList.inViewer(window) {
                AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
        case .nothing: break
        }
    }

    /// `g g` and `G`: selects the first or last row Mail's list has, shows it, and gives the
    /// list the keyboard.
    static func selectEnd(last: Bool) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let window = AXMenuNode.element(app, kAXFocusedWindowAttribute),
              let list = AXSelectableList.inViewer(window), !list.rows.isEmpty else { return }
        let row = last ? list.rows.count - 1 : 0
        _ = list.select([row])
        AXUIElementPerformAction(list.rows[row], "AXScrollToVisible" as CFString)
        AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Esc on a message open in its own window: its close button, else File › Close.
    /// When a key last closed a message window, so its repeats are dropped.
    static var lastCloseAt = Date.distantPast

    static func close(_ window: AXUIElement) {
        lastCloseAt = Date()
        let result = MailKeys.closeOnce(AXClosableWindow(element: window))
        KeysLog.note("close: \(result)")
        // Only a check afterwards, never another action.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { KeysLog.note("close: window still open: \(AXMenuNode.string(window, kAXRoleAttribute) != nil)") }
        }
    }

    /// Esc and `* n`: select none in the focused message list.
    static func clearSelection() {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute), let list = AXSelectableList(focused: focused) else { return }
        _ = MailKeys.clearSelection(list)
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

/// The Message-IDs selected in the list when OpenShelf's `o` opened each message window
/// (2026-11-20). A window opened any other way has none, and `e` and `x` there act on the
/// open message alone.
@MainActor
enum MailWindowBindings {
    private static var bound: [(window: AXUIElement, ids: Set<String>)] = []

    static func bind(_ window: AXUIElement, ids: Set<String>) {
        prune()
        bound.removeAll { CFEqual($0.window, window) }
        bound.append((window, ids))
    }

    static func ids(for window: AXUIElement) -> Set<String>? {
        prune()
        return bound.first { CFEqual($0.window, window) }?.ids
    }

    /// A closed window stops answering.
    private static func prune() {
        bound.removeAll { AXMenuNode.string($0.window, kAXRoleAttribute) == nil }
    }
}

/// Why a Mail single key was taken or passed outside the message list (2026-11-20: Esc and
/// o failed in a message window), in ~/Library/Logs/OpenShelf/keys.log. Only command keys'
/// names, and only in the viewer or a message window, never in a message being written,
/// so nothing typed is ever logged.
@MainActor
enum KeysLog {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenShelf/keys.log")
    }

    static func note(_ line: String) {
        SnoozeLog.append([line], to: fileURL)
    }
}

/// A Mail window behind the close rule: its own close button, read and pressed once.
@MainActor
struct AXClosableWindow: MailKeys.ClosableWindow {
    let element: AXUIElement

    var isMainViewer: Bool { MailKeys.isMainViewer(AXDialogNode(element: element)) }

    func pressCloseButton() -> Bool? {
        guard let button = AXMenuNode.element(element, kAXCloseButtonAttribute) else { return nil }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
}
