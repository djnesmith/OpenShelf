import AppKit

/// Moving through Mail's own Message › Move to menu (David, 2026-11-20: "it should remove the
/// label if we are moving it to another folder or Inbox"; he is fine with the menu flashing
/// open). Scripted moves only copy on his Gmail account; Mail's own Move removes the message
/// from where it was. The folder levels are built only when their submenu opens, so each
/// level is opened in turn and waited for. Any doubt cancels every opened menu and does
/// nothing.
@MainActor
enum MoveMenu {
    /// A menu level the walk can open, read and cancel.
    @MainActor protocol Node {
        var title: String { get }
        var isEnabled: Bool { get }
        /// The items of its menu, as Mail shows them now.
        var items: [Node] { get }
        /// Opens its menu (a bar item or a submenu item), or for a plain item does it.
        func press() -> Bool
        /// Closes its menu, if open.
        func cancel()
        /// Whether its menu shows now.
        var isOpen: Bool { get }
    }

    /// Each level's accepted titles, top first: Message, Move to, the account (On My Mac for
    /// none), then each folder; Mail's menu shows an IMAP "INBOX" as "Inbox".
    static func titles(for mailbox: MailFiling.Mailbox) -> [[String]] {
        let folders = mailbox.chain.enumerated().map { index, name in
            index == 0 && name.uppercased() == "INBOX" ? [name, "Inbox"] : [name]
        }
        return [["Message"], ["Move to"], [mailbox.account.isEmpty ? "On My Mac" : mailbox.account]] + folders
    }

    struct Limits {
        /// How long one level may take to fill in.
        var level: Duration = .milliseconds(500)
        /// The whole walk.
        var total: Duration = .seconds(2)
        var poll: Duration = .milliseconds(25)
    }

    enum Outcome: Equatable {
        /// The folder's item was pressed; Mail closes its menus itself.
        case pressed
        /// Nothing pressed; every opened menu was cancelled.
        case cancelled(reason: String, closed: Bool)
    }

    /// Opens each level, waits for its items, and presses the folder. `log` gets one line per
    /// step: the level number, how many items it had, the time; never a title.
    /// `anyOpen` asks the menu bar whether any of its menus shows.
    static func walk(_ titles: [[String]], bar: [Node], anyOpen: () -> Bool, limits: Limits = Limits(), log: (String) -> Void) async -> Outcome {
        let clock = ContinuousClock()
        let started = clock.now
        func ms() -> Int { Int((clock.now - started) / .milliseconds(1)) }
        var opened: [Node] = []

        // Cancels every opened menu, deepest first; if the bar still shows one after 300 ms,
        // once more. The answer says whether the bar is closed.
        func cancelAll(_ reason: String) async -> Outcome {
            for node in opened.reversed() { node.cancel() }
            var closed = !anyOpen()
            if !closed {
                try? await Task.sleep(for: .milliseconds(300))
                if anyOpen() {
                    for node in opened.reversed() { node.cancel() }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                closed = !anyOpen()
            }
            log("menu: \(reason); cancelled \(opened.count) open menu\(opened.count == 1 ? "" : "s"), menu closed: \(closed ? "yes" : "no"), \(ms()) ms")
            return .cancelled(reason: reason, closed: closed)
        }

        func unique(_ wanted: [String], in items: [Node]) -> Node? {
            let matches = items.filter { wanted.contains($0.title) }
            return matches.count == 1 ? matches[0] : nil
        }

        guard let first = titles.first, let top = unique(first, in: bar) else {
            log("menu: level 1 not found among \(bar.count) bar items, \(ms()) ms")
            return .cancelled(reason: "no Message menu", closed: true)
        }
        // Mail may answer a press late while its menu tracks, so a level counts as open when
        // its items show up within the level's time.
        _ = top.press()
        opened.append(top)
        var current = top
        for level in 1..<titles.count {
            // Wait for this level's items: Mail fills a folder level only once it opens.
            let levelStart = clock.now
            var items = current.items
            var match = unique(titles[level], in: items)
            while match == nil, clock.now - levelStart < limits.level, clock.now - started < limits.total {
                try? await Task.sleep(for: limits.poll)
                items = current.items
                match = unique(titles[level], in: items)
            }
            guard let match else {
                let count = items.filter { titles[level].contains($0.title) }.count
                return await cancelAll("level \(level + 1) of \(titles.count): \(count == 0 ? "not found" : "\(count) matches") among \(items.count) items")
            }
            log("menu: level \(level + 1) of \(titles.count) found among \(items.count) items, \(ms()) ms")
            guard clock.now - started < limits.total else { return await cancelAll("over the time limit") }
            guard match.isEnabled else { return await cancelAll("level \(level + 1) is off") }
            if level == titles.count - 1 {
                // The folder: Mail moves and closes its menus.
                let answered = match.press()
                log("menu: pressed the folder (\(answered ? "ok" : "no answer")), \(ms()) ms")
                return .pressed
            }
            _ = match.press()
            opened.append(match)
            current = match
        }
        return await cancelAll("no folder level")
    }
}

/// A Mail menu bar item or menu item, through Accessibility.
@MainActor
struct AXMoveMenuNode: MoveMenu.Node {
    let element: AXUIElement

    var title: String { AXMenuNode.string(element, kAXTitleAttribute) ?? "" }
    var isEnabled: Bool { AXMenuNode(element: element).isEnabled }
    var items: [MoveMenu.Node] { AXMenuNode.childElements(element).flatMap { AXMenuNode.childElements($0).map(AXMoveMenuNode.init) } }

    /// AXPress: opens a bar item's menu or a submenu, or does a plain item. Mail may answer
    /// late while its menu is tracking (the same AXError -25204 seen on Schedule), so a
    /// missing answer is judged by `isOpen` afterwards.
    func press() -> Bool { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success }

    func cancel() {
        for menu in AXMenuNode.childElements(element) { AXUIElementPerformAction(menu, kAXCancelAction as CFString) }
        AXUIElementPerformAction(element, kAXCancelAction as CFString)
    }

    /// A bar item or submenu item shows its menu while it is selected.
    var isOpen: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}

/// Mail's Move to menu on the user's key press, checked from the message list afterwards.
@MainActor
enum MailMoveMenuRoute {
    /// Moves the main viewer's selection through Message › Move to, or nil when the menu
    /// can't be used (Mail not in front with its main viewer); the script is used then.
    static func move(to mailbox: MailFiling.Mailbox) async -> MailFiling.MoveReport? {
        let clock = ContinuousClock()
        let started = clock.now
        func ms() -> Int { Int((clock.now - started) / .milliseconds(1)) }
        // The picker must be gone and its Return finished before Mail's menu opens, so the
        // panel can't hold the keyboard while the menu tracks.
        while MailboxPicker.shared.isOpen || MailMenu.running?.isActive != true, clock.now - started < .seconds(1) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard let mail = MailMenu.running, mail.isActive, !MailboxPicker.shared.isOpen else {
            KeysLog.note("move menu: Mail not in front after the picker closed; using the script")
            return nil
        }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeys.isMainViewer(AXDialogNode(element: viewer)),
              let barElement = AXMenuNode.element(app, kAXMenuBarAttribute) else {
            KeysLog.note("move menu: Mail's main viewer isn't in front; using the script")
            return nil
        }
        let before = await MailKeyActions.snapshot(viewer)
        guard !before.selected.isEmpty else {
            return MailFiling.MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Select a message in Mail first")
        }
        // Mail's Move to acts on the list's selection when the list has the keyboard.
        if let list = AXSelectableList.inViewer(viewer) {
            AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        try? await Task.sleep(for: .milliseconds(100))
        let bar = AXMenuNode.childElements(barElement).map(AXMoveMenuNode.init)
        let titles = MoveMenu.titles(for: mailbox)
        KeysLog.note("move menu: \(before.selected.count) selected, \(before.rows) rows, \(titles.count) levels, \(ms()) ms")
        let outcome = await MoveMenu.walk(titles, bar: bar, anyOpen: { bar.contains { $0.isOpen } }, log: KeysLog.note)
        switch outcome {
        case .cancelled(let reason, let closed):
            SnoozeLog.append(["move menu: cancelled (\(reason)), menu closed: \(closed ? "yes" : "no"), \(ms()) ms; nothing moved"], to: MailScript.logURL)
            return MailFiling.MoveReport(outcome: .notMoved, title: "Not moved",
                                         subtitle: closed ? "Couldn't find that folder in Mail's Move to menu" : "Mail's menu may still be open; press Esc")
        case .pressed:
            var after = before
            var result = MailKeys.ActionOutcome.unchanged
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(250))
                after = await MailKeyActions.snapshot(viewer)
                result = MailKeys.outcome(before, after, .rowsLeave)
                if result == .changed { break }
            }
            let stillOpen = bar.contains { $0.isOpen }
            let line = "move menu: rows \(before.rows) → \(after.rows), \(before.selected.intersection(after.selected).count) of \(before.selected.count) selected remain, menu closed: \(stillOpen ? "no" : "yes"), \(ms()) ms"
            KeysLog.note(line)
            SnoozeLog.append([line], to: MailScript.logURL)
            let count = before.selected.count == 1 ? "1 message" : "\(before.selected.count) messages"
            if stillOpen { return MailFiling.MoveReport(outcome: .partial, title: "Check \(mailbox.shown) in Mail", subtitle: "Mail's menu may still be open; press Esc") }
            switch result {
            case .changed: return MailFiling.report(.moved, total: before.selected.count, to: mailbox)
            case .ambiguous: return MailFiling.MoveReport(outcome: .partial, title: "Not sure it moved", subtitle: "Check \(count) in \(mailbox.shown)")
            case .unchanged: return MailFiling.MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Mail showed no change")
            }
        }
    }
}
