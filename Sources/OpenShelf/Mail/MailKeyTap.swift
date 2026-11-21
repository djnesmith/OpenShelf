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
    /// Double-clicks while Mail is in front, so a message window opened from the list is
    /// bound like one opened with `o`. A global mouse monitor needs no extra permission.
    private var clickMonitor: Any?

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
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2 else { return }
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { MailKeyActions.bindAfterDoubleClick(cocoaPoint: point) }
        }
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func remove() {
        pending = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        MailKeyHelp.shared.close()
    }

    /// Whether the tap takes this key from Mail. False (the key goes to Mail) whenever in doubt.
    /// `ownPanelHasKeyboard` and `focusAllows` are parameters for tests.
    func takes(type: CGEventType, event: CGEvent, ownPanelHasKeyboard: Bool = NSApp.keyWindow != nil,
               focusAllows: @MainActor (CGEvent, MailKeys.Outcome) -> Bool = MailKeyTap.focusAllows,
               escapePlanner: @MainActor (CGEvent) -> MailKeys.EscapePlan = MailKeyTap.escapePlan) -> Bool {
        // macOS turns a slow tap off; it is turned back on, and the key passes.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, var key = Self.character(of: event) else { return false }
        // ⌃N and ⌃P are j and k, checked as the plain keys: a pending g or * is dropped, so
        // ⌃N after g is not g j.
        var checked = event
        let controlOnly = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]) == .maskControl
        if let alias = MailKeys.controlAlias(key, controlOnly: controlOnly), let plain = event.copy() {
            plain.flags = event.flags.subtracting(.maskControl)
            key = alias
            checked = plain
            pending = nil
        }
        // One action per key down: a held Esc repeats, and after a close the next window in
        // front would get it (2026-11-20). Repeats right after a close are dropped.
        if key == MailKeys.escape, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
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
        if key == MailKeys.escape, pending == nil {
            let plan = escapePlanner(event)
            switch plan {
            case .pass: return false
            case .clearSelection: DispatchQueue.main.async { MainActor.assumeIsolated { MailKeyActions.clearSelection() } }
            case .focusList: DispatchQueue.main.async { MainActor.assumeIsolated { MailKeyActions.backToList() } }
            }
            return true
        }
        let outcome = MailKeys.outcome(for: key, pending: pending)
        pending = nil
        guard outcome != .pass, focusAllows(checked, outcome) else { return false }
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

    /// Esc's plan from Mail's focus, read with a short timeout; anything unreadable passes.
    static func escapePlan(_ event: CGEvent) -> MailKeys.EscapePlan {
        guard let mail = MailMenu.running else { return .pass }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return .pass }
        let window = AXMenuNode.element(app, kAXFocusedWindowAttribute)
        let inViewer = window.map { MailKeys.isMainViewer(AXDialogNode(element: $0)) } ?? false
        let messageList = inViewer ? window.flatMap(AXSelectableList.inViewer) : nil
        let inList = MailKeys.isInside(focused, messageList?.list, parent: { AXMenuNode.element($0, kAXParentAttribute) }, same: { CFEqual($0, $1) })
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXEditable" as CFString, &editable)
        // A Mail menu showing: its bar item is selected.
        let menuOpen = AXMenuNode.element(app, kAXMenuBarAttribute).map { bar in
            AXMenuNode.childElements(bar).contains { item in
                var selected: CFTypeRef?
                return AXUIElementCopyAttributeValue(item, kAXSelectedAttribute as CFString, &selected) == .success && (selected as? Bool) == true
            }
        } ?? true
        let plan = MailKeys.escapePlan(
            focusedRole: AXMenuNode.string(focused, kAXRoleAttribute), isEditable: (editable as? Bool) ?? false,
            inMessageList: inList, inViewer: inViewer, selectedCount: inList ? (messageList?.selectedRows.count ?? 0) : 0,
            hasSheetOrPopover: hasSheetOrPopover(app), menuOpen: menuOpen,
            modifiers: event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty ? [] : .other,
            mailHasFocus: MailMenu.hasKeyboardFocus())
        if inViewer { KeysLog.note("Esc in the viewer (\(AXMenuNode.string(focused, kAXRoleAttribute) ?? "?"), in the list \(inList)): \(plan)") }
        return plan
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
            action: action,
            gPrefix: outcome == .prefix("g")
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
            if !conversationAction(archive: title == "Archive") { performVerified(title, under: top) }
        case .menu("Edit", "Undo"):
            undo()
        case .menu("File", "New Message"):
            if press("New Message", under: "File") { focusTo() }
        case .toggleRead:
            let bar = MailMenu.menuBar() ?? []
            guard let title = MailKeys.toggleReadTitle(shows: { item($0, under: "Message", in: bar) != nil }) else {
                _ = notPressed("Mark as Read", "no Mark as Read or Mark as Unread in Mail's Message menu")
                return
            }
            performVerified(title, under: "Message")
        case .menu(let top, let title) where verifiedTitles.contains(title):
            performVerified(title, under: top)
        case .menu(let top, let title):
            press(title, under: top)
        case .favorite(let name):
            goToUnified(name)
        case .nextMessage:
            moveSelection(by: 1)
        case .previousMessage:
            moveSelection(by: -1)
        case .archiveThenPrevious:
            if conversationAction(archive: true) { return }
            performVerified("Archive", under: "Message") { moveSelection(by: -1) }
        case .snooze:
            MailHelpers.shared.showPrompt()
        case .file:
            MailFiling.showPicker()
        case .showKeys:
            MailKeyHelp.shared.show()
        case .clearSelection:
            clearSelection()
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
        guard item.press() else { return notPressed(title, "“\(title)” didn't respond") }
        KeysLog.note("menu \(top) › \(title): pressed")
        return true
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
        // The item in the menu itself comes first: a deep search alone found a same-titled
        // item in a submenu earlier in the menu (2026-11-20: `e` pressed nothing visible;
        // "Move to" lists a mailbox named "Archive" before Message › Archive).
        if let exact = MailMenu.find(submenu.map { [top, $0, title] } ?? [top, title], in: bar) { return exact }
        guard var menu = bar.first(where: { $0.title == top }) else { return nil }
        if let submenu {
            guard let inner = MailMenu.findAnywhere(submenu, in: menu.children) else { return nil }
            menu = inner
        }
        return MailMenu.findAnywhere(title, in: menu.children)
    }

    /// Commands whose effect is checked in Mail after the key (archive, delete, junk, flag,
    /// read, mute).
    static let verifiedTitles: Set<String> = ["Archive", "Delete", "Move to Junk", "Toggle Flag", "Mark as Read", "Mark as Unread", "Mute"]

    /// Does the command in the main viewer and checks it happened: the viewer's toolbar
    /// button first (one press), then the list gets the keyboard and the menu item is
    /// pressed; each try is followed by up to a second of looking at Mail, and a try that
    /// changed something ends it. Nothing changed: a toast says so (2026-11-20: Message ›
    /// Archive answered "pressed" and Mail did nothing).
    static func performVerified(_ title: String, under top: String, then afterDone: (() -> Void)? = nil) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeys.isMainViewer(AXDialogNode(element: viewer)) else {
            // Not the main viewer: the menu item, as before.
            if press(title, under: top) { afterDone?() }
            return
        }
        let kind = MailKeys.verification(for: title)
        Task { @MainActor in
            var before = await snapshot(viewer)
            let focusRole = AXMenuNode.element(app, kAXFocusedUIElementAttribute).flatMap { AXMenuNode.string($0, kAXRoleAttribute) } ?? "?"
            KeysLog.note("\(title): focus \(focusRole), \(before.rows) rows, \(before.selected.count) selected")
            let inbox = MailKeys.showsUnified("Inbox", windowTitle: AXMenuNode.string(viewer, kAXTitleAttribute))
            let clear = MailKeys.reminderToClear(title: title, bar: MailMenu.menuBar() ?? [], viewerShowsInbox: inbox, selected: before.selected.count)
            if title == "Archive", let clear {
                switch await clearReminder(clear, in: viewer, before: before) {
                case .done:
                    afterDone?()
                    return
                case .stop:
                    ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Reminder cleared, nothing archived",
                                                      subtitle: "Mail's selection moved; check the list"), for: .seconds(5))
                    return
                case .archive(let now):
                    before = now
                }
            }
            let label = MailKeys.toolbarLabel(for: title)
            let button = label.flatMap { MailKeys.toolbarButton($0, in: AXDialogNode(element: viewer)) } as? AXDialogNode
            if label != nil, button == nil { KeysLog.note("\(title): no \(label!) button in the viewer's toolbar") }
            // Delete with a reminder to clear: one press only. A second Delete on a message
            // already in Trash would erase it.
            let clearAfterDelete = title == "Delete" && clear != nil
            let originalBefore = before
            var tried: [MailKeys.ActionRoute] = []
            var last: MailKeys.ActionOutcome?
            var deletePressed = false
            while true {
                // Delete never takes a second route: a message Delete moved to Trash can stay in
                // the list (a fired reminder), and a second Delete there would erase it.
                let step = MailKeys.nextActionStep(tried: tried, last: last, toolbarAvailable: button != nil && MailKeys.mayRetryOnToolbar(title))
                if clearAfterDelete, deletePressed, step == .gaveUp || { if case .unsure = step { true } else { false } }() {
                    await clearAfterDeleting(originalBefore, in: viewer, then: afterDone)
                    return
                }
                switch step {
                case .done(let route):
                    KeysLog.note("\(title): done via \(route)\(kind == .none ? " (not verifiable)" : "")")
                    afterDone?()
                    return
                case .unsure(let route):
                    KeysLog.note("\(title): unsure after \(route); no second route")
                    ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Not sure \(title) worked",
                                                      subtitle: "Mail changed, but no message left the list"), for: .seconds(5))
                    return
                case .gaveUp:
                    KeysLog.note("\(title): no change after every route")
                    ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "\(title) did nothing",
                                                      subtitle: "Mail showed no change; ⌘-key in Mail still works"), for: .seconds(5))
                    return
                case .attempt(let route):
                    tried.append(route)
                    switch route {
                    case .toolbar:
                        let answer = button.map { AXUIElementPerformAction($0.element, kAXPressAction as CFString) } ?? .failure
                        KeysLog.note("\(title): pressed the toolbar button, \(answer == .success ? "ok" : "AXError \(answer.rawValue)")")
                    case .listThenMenu:
                        if let list = AXSelectableList.inViewer(viewer) {
                            AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                        deletePressed = press(title, under: top)
                    }
                    last = await waitForOutcome(from: before, in: viewer, kind, title: title)
                    KeysLog.note("\(title): \(route) \(last.map { "\($0)" } ?? "?")")
                }
            }
        }
    }

    /// `x`'s second half: Delete left the reminded rows in the list, so Clear Reminder is
    /// pressed while Mail still selects only those messages; proven when they leave.
    private static func clearAfterDeleting(_ before: MailKeys.ListSnapshot, in viewer: AXUIElement, then afterDone: (() -> Void)?) async {
        // Two readings 300 ms apart must agree, so a slow Mail isn't caught mid-move.
        let first = await snapshot(viewer)
        try? await Task.sleep(for: .milliseconds(300))
        let now = await snapshot(viewer)
        let item = MailMenu.find(MailMenu.clearReminder, in: MailMenu.menuBar() ?? [])
        guard first == now, MailKeys.mayClearAfterDelete(before, now), let item, item.isEnabled else {
            KeysLog.note("Delete: rows stayed; Clear Reminder not pressed (selection kept \(MailKeys.mayClearAfterDelete(before, now)), item on \(item?.isEnabled ?? false))")
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Not sure Delete worked",
                                              subtitle: "The messages are still in the list"), for: .seconds(5))
            return
        }
        switch await clearReminder(item, in: viewer, before: now) {
        case .done:
            afterDone?()
        case .stop, .archive:
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Not sure Delete worked",
                                              subtitle: "Mail still shows the messages after Clear Reminder"), for: .seconds(5))
        }
    }

    enum ClearResult { case done, stop, archive(MailKeys.ListSnapshot) }

    /// Presses Clear Reminder with the list holding the keyboard (as Archive needs), then up
    /// to 1.5 s of looking at the list. Logs counts only.
    private static func clearReminder(_ item: MenuNode, in viewer: AXUIElement, before: MailKeys.ListSnapshot) async -> ClearResult {
        if let list = AXSelectableList.inViewer(viewer) { AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
        try? await Task.sleep(for: .milliseconds(100))
        let pressed = item.press()
        var after = before
        var next = MailKeys.AfterClear.stop
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(250))
            after = await snapshot(viewer)
            let stillOn = MailMenu.find(MailMenu.clearReminder, in: MailMenu.menuBar() ?? [])?.isEnabled ?? true
            next = MailKeys.afterClearingReminder(before, after, clearStillOn: stillOn)
            if next != .stop { break }
        }
        // Archive only on a list that has settled: one more reading must agree.
        if next == .archive {
            try? await Task.sleep(for: .milliseconds(300))
            if await snapshot(viewer) != after { next = .stop }
        }
        KeysLog.note("Clear Reminder \(pressed ? "pressed" : "didn't respond"), rows \(before.rows) → \(after.rows), \(before.selectedRows) selected rows: \(next)")
        switch next {
        case .done: return .done
        case .stop: return .stop
        case .archive: return .archive(after)
        }
    }

    /// Up to 1.5 s of looking for the command's effect: stops early when proven; else the
    /// last reading. Logs the rows before and after and how many selected messages remain.
    private static func waitForOutcome(from before: MailKeys.ListSnapshot, in viewer: AXUIElement, _ kind: MailKeys.Verification, title: String) async -> MailKeys.ActionOutcome {
        if kind == .none { return .changed }
        var after = before
        var result = MailKeys.ActionOutcome.unchanged
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(250))
            after = await snapshot(viewer)
            result = MailKeys.outcome(before, after, kind)
            if result == .changed { break }
        }
        KeysLog.note("\(title): rows \(before.rows) → \(after.rows), \(before.selected.intersection(after.selected).count) of \(before.selected.count) selected remain")
        return result
    }

    /// The viewer's list row count and the selected messages' ids, flag and read states
    /// (Mail's AppleScript; never a subject or body).
    static func snapshot(_ viewer: AXUIElement) async -> MailKeys.ListSnapshot {
        let list = AXSelectableList.inViewer(viewer)
        let rows = list?.rows.count ?? 0
        let source = MailScripts.selectionState
        let text = await MailScript.run("selection state", source).text ?? ""
        var snapshot = MailKeys.ListSnapshot(rows: rows, selected: [], selectedRows: list?.selectedRows.count ?? 0)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count == 3 else { continue }
            snapshot.selected.insert(parts[0])
            snapshot.flagged[parts[0]] = parts[1] == "true"
            snapshot.read[parts[0]] = parts[2] == "true"
        }
        return snapshot
    }

    /// `e` or `x` in a message window: what Archive or Delete does with that message's row
    /// selected in the list. False when the front window isn't a message window (the caller
    /// then presses the menu item as usual).
    static func conversationAction(archive: Bool, scripting: MailScripting = AppleScriptMail()) -> Bool {
        guard let mail = MailMenu.running else { return false }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard MailKeyTap.isMessageWindow(app), let window = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return false }
        Task { @MainActor in
            // Mail answers on the scripts' queue; the window is checked again afterwards.
            let current = Set(await scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
            guard let front = AXMenuNode.element(app, kAXFocusedWindowAttribute), CFEqual(front, window), MailKeyTap.isMessageWindow(app) else {
                KeysLog.note("\(archive ? "e" : "x"): the message window left the front while Mail answered; nothing done")
                ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Nothing \(archive ? "archived" : "trashed")",
                                                  subtitle: "The message window changed while Mail answered"), for: .seconds(4))
                return
            }
            var windowsValue: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
            // The main viewer by its structure; a message window shares its id prefix.
            let viewer = ((windowsValue as? [AXUIElement]) ?? []).first { MailKeys.isMainViewer(AXDialogNode(element: $0)) }
            let list = viewer.flatMap(AXSelectableList.inViewer)
            let bound = MailWindowBindings.ids(for: window)
            switch MailKeys.conversationPlan(bound: bound, selectedRows: list?.selectedRows.count ?? 0, current: current) {
            case .viaList(let count):
                close(window)
                if let viewer { AXUIElementPerformAction(viewer, kAXRaiseAction as CFString) }
                try? await Task.sleep(for: .milliseconds(400))
                // Checked from the elements now, never from the close press's answer.
                let gone = AXMenuNode.string(window, kAXRoleAttribute) == nil
                let frontNow = AXMenuNode.element(app, kAXFocusedWindowAttribute)
                let frontIsViewer = frontNow.map { MailKeys.isMainViewer(AXDialogNode(element: $0)) } ?? false
                let now = Set(await scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
                let ok = MailKeys.mayPressInViewer(messageWindowGone: gone, frontIsMainViewer: frontIsViewer, bound: bound, current: now)
                KeysLog.note("\(archive ? "e" : "x") via the list: window gone \(gone), viewer in front \(frontIsViewer), same selection \(bound == now): \(ok ? "pressing" : "not pressing")")
                guard ok else {
                    if !gone { actOnOpenMessage(window, archive: archive, reason: "conversation not confirmed") } else {
                        ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Nothing \(archive ? "archived" : "trashed")",
                                                          subtitle: "The list changed after the window closed"), for: .seconds(4))
                    }
                    return
                }
                // Checked in the viewer afterwards (rows left, selection gone), as e and x
                // from the list are; a press's answer alone proves nothing.
                KeysLog.note("\(archive ? "e" : "x") via the list: \(count) message\(count == 1 ? "" : "s") selected there")
                performVerified(archive ? "Archive" : "Delete", under: archive ? "Message" : "Edit")
            case .thisMessage:
                actOnOpenMessage(window, archive: archive, reason: "conversation not confirmed")
            }
        }
        return true
    }

    /// Archive or Delete on the open message through its window's own toolbar button, one
    /// press, never a menu item that acts on whatever is in front. The press's answer is
    /// only logged (it can be an error while Mail acts); what happened is read from the
    /// window afterwards.
    static func actOnOpenMessage(_ window: AXUIElement, archive: Bool, reason: String) {
        let title = archive ? "Archive" : "Delete"
        guard let button = MailKeys.toolbarButton(title, in: AXDialogNode(element: window)) as? AXDialogNode else {
            KeysLog.note("\(title) on the open message: no \(title) button in its window's toolbar")
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Nothing \(archive ? "archived" : "trashed")",
                                              subtitle: "The message window has no \(title) button"), for: .seconds(4))
            return
        }
        let answer = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        KeysLog.note("\(title) on the open message: pressed its button, \(answer == .success ? "ok" : "AXError \(answer.rawValue)")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated {
                let gone = AXMenuNode.string(window, kAXRoleAttribute) == nil
                let result = MailKeys.openMessageResult(buttonFound: true, windowGone: gone)
                KeysLog.note("\(title) on the open message: \(result)")
                switch result {
                case .done:
                    ToastController.shared.show(Toast(systemImage: archive ? "archivebox" : "trash", title: "\(archive ? "Archived" : "Trashed") 1 message",
                                                      subtitle: "\(reason.prefix(1).uppercased() + reason.dropFirst()), so only this one"), for: .seconds(4))
                case .unsure:
                    ToastController.shared.show(Toast(systemImage: archive ? "archivebox" : "trash", title: "\(title) pressed",
                                                      subtitle: "The window is still open; check the message"), for: .seconds(4))
                case .noButton:
                    break
                }
            }
        }
    }

    /// `o`: opens the selected message, and remembers which Message-IDs were selected for
    /// the window it opens, so `e` and `x` there can tell the list still holds that row.
    static func openAndBind(scripting: MailScripting = AppleScriptMail()) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return }
        Task { @MainActor in
            let ids = Set(await scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
            // Opened only from the same viewer still in front, now that Mail has answered.
            guard let front = AXMenuNode.element(app, kAXFocusedWindowAttribute), CFEqual(front, viewer),
                  MailKeys.isMainViewer(AXDialogNode(element: front)) else {
                KeysLog.note("o: the viewer left the front while Mail answered; nothing opened")
                return
            }
            // Mail's "Open Message" (MainMenu.loctable 1772) is looked for in every menu.
            guard pressAnywhere("Open Message"), !ids.isEmpty else { return }
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if let window = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeyTap.isMessageWindow(app) {
                    MailWindowBindings.bind(window, ids: ids)
                    return
                }
            }
        }
    }

    /// A double-click in the viewer's message list (David, 2026-11-20: e and x on a message
    /// opened by double-click should act on the whole conversation, as for `o`): the
    /// selection's Message-IDs are read and bound to the message window that opens within
    /// 2 s, exactly as `o` binds them. A double-click anywhere else binds nothing, so a
    /// window opened from a notification or a search is never tied to the list's selection.
    static func bindAfterDoubleClick(cocoaPoint: NSPoint, scripting: MailScripting = AppleScriptMail()) {
        guard let mail = MailMenu.running, mail.isActive else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return }
        let isViewer = MailKeys.isMainViewer(AXDialogNode(element: viewer))
        // The visible list: its scroll area, since the table itself is as tall as all its rows.
        let listArea = AXSelectableList.inViewer(viewer).map { list in
            AXMenuNode.element(list.list, kAXParentAttribute).flatMap { AXMenuNode.string($0, kAXRoleAttribute) == "AXScrollArea" ? $0 : nil } ?? list.list
        }
        let point = MailKeys.axPoint(fromCocoa: cocoaPoint, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        guard MailKeys.bindsAfterDoubleClick(viewerInFront: isViewer, listFrame: listArea.flatMap(frame), point: point) else { return }
        Task { @MainActor in
            let ids = Set(await scripting.selectedMessages().map(\.id).filter { !$0.isEmpty })
            guard !ids.isEmpty else { KeysLog.note("double-click: no selection read; window not bound"); return }
            for _ in 0..<20 {
                if let window = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeyTap.isMessageWindow(app) {
                    if MailWindowBindings.ids(for: window) == nil { MailWindowBindings.bind(window, ids: ids) }
                    KeysLog.note("double-click: message window bound to \(ids.count) message\(ids.count == 1 ? "" : "s")")
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            KeysLog.note("double-click: no message window opened within 2 s")
        }
    }

    /// An element's frame in Accessibility's screen coordinates (top-left origin).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue, CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// After `c`: once the new message's window is in front (up to 2 s), its To field gets
    /// the keyboard unless it has it already, and it is read back. keys.log says where focus
    /// was (role only) and what happened.
    static func focusTo() {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let window = AXMenuNode.element(app, kAXFocusedWindowAttribute),
                      MailKeyTap.facts(window, app: app).hasComposeControls else { continue }
                guard let to = MailKeys.toField(in: AXDialogNode(element: window)) as? AXDialogNode else {
                    KeysLog.note("c: new message open, no To field found")
                    ToastController.shared.show(Toast(systemImage: "envelope", title: "New message: To not found",
                                                      subtitle: "Click the To field"), for: .seconds(4))
                    return
                }
                @MainActor func inTo() -> Bool {
                    MailKeys.isInside(AXMenuNode.element(app, kAXFocusedUIElementAttribute), to.element,
                                      parent: { AXMenuNode.element($0, kAXParentAttribute) }, same: { CFEqual($0, $1) })
                }
                let was = AXMenuNode.element(app, kAXFocusedUIElementAttribute).flatMap { AXMenuNode.string($0, kAXRoleAttribute) } ?? "none"
                if inTo() { KeysLog.note("c: To had the keyboard already"); return }
                AXUIElementSetAttributeValue(to.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                try? await Task.sleep(for: .milliseconds(150))
                let ok = inTo()
                KeysLog.note("c: focus was \(was) (To field: \(to.role), id \(to.identifier ?? "none")); To has the keyboard \(ok)")
                if !ok {
                    ToastController.shared.show(Toast(systemImage: "envelope", title: "New message: cursor not in To",
                                                      subtitle: "Click the To field"), for: .seconds(4))
                }
                return
            }
            KeysLog.note("c: no new message window within 2 s")
        }
    }

    /// `z`: Mail's Undo item, whatever it is titled now ("Undo Archive"), then a look at
    /// the viewer: rows, selection, flag and read states. A change ends it quietly;
    /// nothing changed after 1.5 s: a toast says so.
    static func undo() {
        guard let bar = MailMenu.menuBar(), let edit = bar.first(where: { $0.title == "Edit" }) else {
            _ = notPressed("Undo", "Mail's menus can't be read"); return
        }
        guard let index = MailKeys.undoIndex(in: edit.children.map(\.title)) else { _ = notPressed("Undo", "no Undo in Mail's Edit menu"); return }
        let item = edit.children[index]
        guard item.isEnabled else { _ = notPressed("Undo", "Mail has nothing to undo here"); return }
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute).flatMap { MailKeys.isMainViewer(AXDialogNode(element: $0)) ? $0 : nil }
        Task { @MainActor in
            var before: MailKeys.ListSnapshot?
            if let viewer { before = await snapshot(viewer) }
            guard item.press() else { _ = notPressed("Undo", "Mail's Undo didn't respond"); return }
            KeysLog.note("menu Edit › Undo: pressed (\(item.title.split(separator: " ").count) word title)")
            guard let viewer, let before else { return }
            var after = before
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(250))
                after = await snapshot(viewer)
                if after != before { break }
            }
            KeysLog.note("undo: rows \(before.rows) → \(after.rows), \(after == before ? "no change" : "changed")")
            if after == before {
                ToastController.shared.show(Toast(systemImage: "arrow.uturn.backward", title: "Not sure Undo worked", subtitle: "Mail showed no change"), for: .seconds(4))
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
        let messageList = AXSelectableList.inViewer(window)?.list
        func focusInList() -> Bool {
            MailKeys.isInside(AXMenuNode.element(app, kAXFocusedUIElementAttribute), messageList,
                              parent: { AXMenuNode.element($0, kAXParentAttribute) }, same: { CFEqual($0, $1) })
        }
        let sendEnabled = MailKeys.sendIsOn(menuRead: MailMenu.menuBar() != nil, send: MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }?.isEnabled)
        let plan = MailKeys.backToList(facts, focusInList: focusInList(), sendEnabled: sendEnabled)
        KeysLog.note("Esc, back to the list: \(plan)")
        switch plan {
        case .close: close(window)
        case .focusList:
            guard let messageList else { KeysLog.note("Esc, back to the list: no message list in the viewer"); return }
            // The list's own focus first; Mail may ignore it when the window itself has focus
            // (2026-11-20, after a g key through the sidebar), so then the app's focus.
            AXUIElementSetAttributeValue(messageList, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            var taken = focusInList()
            if !taken {
                AXUIElementSetAttributeValue(app, kAXFocusedUIElementAttribute as CFString, messageList)
                taken = focusInList()
            }
            KeysLog.note("Esc, back to the list: list has the keyboard: \(taken ? "yes" : "no")")
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
              let list = AXSelectableList.inViewer(window), !list.rows.isEmpty else {
            KeysLog.note("\(last ? "G" : "g g"): no message list in front")
            return
        }
        let row = last ? list.rows.count - 1 : 0
        KeysLog.note("\(last ? "G" : "g g"): row \(row + 1) of \(list.rows.count)")
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

    /// `g i`, `g f`, `g s`, `g t`, `g d`, `g a`: the unified mailbox, found among Mail's
    /// Favorites at press time by its title ("All Inboxes", or "Inbox" with one account),
    /// else its row in the sidebar; then the viewer's title is checked.
    static func goToUnified(_ name: String) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let wanted = MailKeys.unifiedTitles(for: name).first ?? name
        var route = "none"
        if let bar = MailMenu.menuBar(), let favorites = MailMenu.find(["Mailbox", "Go to Favorite Mailbox"], in: bar)?.children,
           let index = MailKeys.unifiedIndex(for: name, in: favorites.map(\.title)), favorites[index].isEnabled, favorites[index].press() {
            route = "Favorites"
        } else if name == MailKeys.allMail {
            // One All Mail per Gmail account: the script picks the selected message's.
            Task { @MainActor in
                let result = MailKeys.allMailResult(await MailScript.run("show all mail", MailScripts.showAllMail).text)
                KeysLog.note("g a: All Mail script \(result)")
                switch result {
                case .selected, .first: checkArrival(name, route: "script (\(result))", app: app)
                case .none:
                    ToastController.shared.show(Toast(systemImage: "tray", title: "No All Mail in Mail", subtitle: "Only Gmail accounts have one"), for: .seconds(4))
                case .failed:
                    ToastController.shared.show(Toast(systemImage: "tray", title: "Couldn't open All Mail", subtitle: "Mail didn't answer; see mail-scripts.log"), for: .seconds(4))
                }
            }
            return
        } else if let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute), selectSidebarRow(name, in: viewer) {
            route = "sidebar"
        }
        guard route != "none" else {
            KeysLog.note("g \(name): not in Mail's Favorites or sidebar")
            // Follow Up, Send Later and Remind Me show in Mail only when they hold something.
            let shownOnlyWhenFull = ["Follow Up", "Send Later", "Remind Me"].contains(name)
            ToastController.shared.show(Toast(systemImage: "tray", title: shownOnlyWhenFull ? "\(wanted) isn't showing in Mail right now" : "\(wanted) isn't in Mail's Favorites",
                                              subtitle: shownOnlyWhenFull ? "Mail shows it when it holds messages" : "Nor in the sidebar; add it to Favorites in Mail"), for: .seconds(5))
            return
        }
        checkArrival(name, route: route, app: app)
    }

    /// 0.6 s later, whether the viewer's title says it shows `name`; a toast if not.
    private static func checkArrival(_ name: String, route: String, app: AXUIElement) {
        let wanted = MailKeys.unifiedTitles(for: name).first ?? name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated {
                let title = AXMenuNode.element(app, kAXFocusedWindowAttribute).flatMap { AXMenuNode.string($0, kAXTitleAttribute) }
                let arrived = MailKeys.showsUnified(name, windowTitle: title)
                KeysLog.note("g \(name): via \(route), viewer shows it: \(arrived)")
                if !arrived {
                    ToastController.shared.show(Toast(systemImage: "tray", title: "Not sure Mail went to \(wanted)",
                                                      subtitle: "Its window doesn't say so"), for: .seconds(4))
                }
            }
        }
    }

    /// Selects the sidebar's row for the unified mailbox `name` (the sidebar is the first
    /// outline in the viewer's "Main Window" split group). False when there is none.
    static func selectSidebarRow(_ name: String, in viewer: AXUIElement) -> Bool {
        guard MailKeys.isMainViewer(AXDialogNode(element: viewer)),
              let split = AXMenuNode.childElements(viewer).first(where: { AXMenuNode.string($0, kAXIdentifierAttribute) == "Main Window" }),
              let sidebar = AXMenuNode.childElements(split).lazy.compactMap({ area in
                  AXMenuNode.childElements(area).first { AXMenuNode.string($0, kAXRoleAttribute) == "AXOutline" }
              }).first else { return false }
        var rowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sidebar, kAXRowsAttribute as CFString, &rowsValue) == .success, let rows = rowsValue as? [AXUIElement] else { return false }
        let labels = rows.map { row in
            MailKeys.sidebarLabel(row, role: { AXMenuNode.string($0, kAXRoleAttribute) }, value: { AXMenuNode.string($0, kAXValueAttribute) },
                                  label: { AXMenuNode.string($0, kAXTitleAttribute) ?? AXMenuNode.string($0, kAXDescriptionAttribute) },
                                  children: { AXMenuNode.childElements($0) })
        }
        guard let index = MailKeys.unifiedIndex(for: name, in: labels) else {
            // Counts only, no names.
            KeysLog.note("sidebar: \(rows.count) rows, \(labels.filter { !$0.isEmpty }.count) with a name read, none matched")
            return false
        }
        return AXUIElementSetAttributeValue(sidebar, kAXSelectedRowsAttribute as CFString, [rows[index]] as CFArray) == .success
    }

    /// Esc and `* n`: select none in the focused message list.
    static func clearSelection() {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute), let list = AXSelectableList(focused: focused) else {
            KeysLog.note("select none: no list in focus")
            return
        }
        KeysLog.note("select none: \(MailKeys.clearSelection(list))")
    }

    /// j and k: the message list's selection moves one row, through Accessibility.
    static func moveSelection(by step: Int) {
        guard let mail = MailMenu.running else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return }
        // A focused row or cell belongs to the list above it. Focus in the reading pane (a
        // message of a conversation) or on the window has no list above it: the viewer's
        // message list then (2026-11-20: j there was taken and moved nothing).
        let list: AXUIElement
        if let above = MailKeys.ancestor(of: focused, parent: { AXMenuNode.element($0, kAXParentAttribute) },
                                         matching: { ["AXTable", "AXOutline"].contains(AXMenuNode.string($0, kAXRoleAttribute) ?? "") }) {
            list = above
        } else if let window = AXMenuNode.element(app, kAXFocusedWindowAttribute), let viewerList = AXSelectableList.inViewer(window)?.list {
            list = viewerList
        } else {
            KeysLog.note("\(step > 0 ? "j" : "k"): no message list here")
            return
        }
        var rowsValue: CFTypeRef?
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXRowsAttribute as CFString, &rowsValue) == .success,
              let rows = rowsValue as? [AXUIElement], !rows.isEmpty else { return }
        AXUIElementCopyAttributeValue(list, kAXSelectedRowsAttribute as CFString, &selectedValue)
        let selected = (selectedValue as? [AXUIElement]) ?? []
        let current = selected.first.flatMap { row in rows.firstIndex { CFEqual($0, row) } }
        let target = MailKeys.row(after: current, by: step, count: rows.count)
        let result = AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, [rows[target]] as CFArray)
        KeysLog.note("\(step > 0 ? "j" : "k"): row \(target + 1) of \(rows.count), \(result == .success ? "selected" : "AXError \(result.rawValue)")")
    }
}

extension MailKeys {
    /// A Cocoa screen point (bottom-left origin) in Accessibility's coordinates (top-left
    /// origin of the primary screen).
    static func axPoint(fromCocoa point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Whether a double-click binds the window it opens: the main viewer in front and the
    /// click inside its message list's visible frame. Anything unreadable binds nothing.
    static func bindsAfterDoubleClick(viewerInFront: Bool, listFrame: CGRect?, point: CGPoint) -> Bool {
        guard viewerInFront, let listFrame, !listFrame.isEmpty else { return false }
        return listFrame.contains(point)
    }

    /// `start` or its nearest ancestor that matches, up to 12 levels; nil if none.
    static func ancestor<T>(of start: T, parent: (T) -> T?, matching: (T) -> Bool) -> T? {
        var node: T? = start
        for _ in 0..<12 {
            guard let current = node else { return nil }
            if matching(current) { return current }
            node = parent(current)
        }
        return nil
    }

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
        OpenShelfFiles.logs.appendingPathComponent("keys.log")
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
