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
        /// Whether it holds a submenu (Mail may fill it only when it opens).
        var hasSubmenu: Bool { get }
    }

    /// Each level's accepted titles, top first: Message, Move to, the account (On My Mac for
    /// none), then each folder; Mail's menu shows an IMAP "INBOX" as "Inbox".
    static func titles(for mailbox: MailFiling.Mailbox) -> [[String]] {
        let folders = mailbox.chain.enumerated().map { index, name in
            index == 0 && name.uppercased() == "INBOX" ? [name, "Inbox"] : [name]
        }
        return [["Message"], ["Move to"], [mailbox.account.isEmpty ? "On My Mac" : mailbox.account]] + folders
    }

    /// The account's own top-level folder names, from the saved listing, with an IMAP INBOX
    /// also as "Inbox" (Mail's menu title).
    static func topFolders(of account: String, cache: [String: [MailFiling.Mailbox]] = MailFiling.loadCache()) -> Set<String> {
        var names = Set((cache[account] ?? []).compactMap { $0.chain.count == 1 ? $0.chain[0] : nil })
        if names.contains(where: { $0.uppercased() == "INBOX" }) { names.insert("Inbox") }
        return names
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
        /// The folder is there but greyed out (Mail greys the mailbox the selected messages
        /// are in); nothing pressed, every opened menu cancelled.
        case folderOff(closed: Bool)
        /// Two folders with the folder's name in the account's section, and nothing tells
        /// which is meant; nothing pressed.
        case ambiguous(closed: Bool)
        /// Nothing pressed; every opened menu was cancelled.
        case cancelled(reason: String, closed: Bool)
    }

    /// A title without the leading spaces Mail may use to indent nested folders.
    static func name(_ node: Node) -> String { String(node.title.drop { $0 == " " || $0 == "\t" }) }
    static func indent(_ node: Node) -> Int { node.title.prefix { $0 == " " || $0 == "\t" }.count }

    /// The shape of an open Move to list, for the log: counts only, never a title.
    static func shape(_ items: [Node]) -> String {
        let separators = items.filter { $0.title.isEmpty }.count
        let indents = items.map(indent)
        return "\(items.count) items, \(items.filter { !$0.isEnabled }.count) off, \(items.filter(\.hasSubmenu).count) with submenus, \(separators) separators, \(indents.filter { $0 > 0 }.count) indented (up to \(indents.max() ?? 0) spaces)"
    }

    enum FlatFind: Equatable {
        case found(Int)
        case notFound
        /// The leaf name is in the section more than once and indentation can't tell which.
        case twoOrMore
    }

    /// A nested folder in one account's section of a flat list (`path` is each level's
    /// accepted names, top first). With indentation: each level among the items under its
    /// parent (indented deeper), at the shallowest indent there. Without: the leaf, if its
    /// name is in the section only once.
    static func flatFind(_ path: [[String]], in section: [Node]) -> FlatFind {
        guard let leaf = path.last else { return .notFound }
        if section.contains(where: { indent($0) > 0 }) {
            var range = Array(section.indices)
            var hit: Int?
            for names in path {
                let shallowest = range.map { indent(section[$0]) }.min() ?? 0
                let found = range.filter { indent(section[$0]) == shallowest && names.contains(name(section[$0])) }
                guard found.count == 1, let index = found.first else { return found.isEmpty ? .notFound : .twoOrMore }
                hit = index
                let depth = indent(section[index])
                range = Array(section.indices.drop { $0 <= index }.prefix { indent(section[$0]) > depth })
            }
            return hit.map(FlatFind.found) ?? .notFound
        }
        let found = section.indices.filter { leaf.contains(name(section[$0])) }
        if found.count > 1 { return .twoOrMore }
        return found.first.map(FlatFind.found) ?? .notFound
    }

    /// One item, for the log: whether it holds a submenu and is enabled; never its title.
    static func describe(_ node: Node) -> String {
        "submenu \(node.hasSubmenu ? "yes" : "no"), enabled \(node.isEnabled ? "yes" : "no")"
    }

    /// The items of one account in Mail's flat Move to list (2026-11-20, David's Mail: Move to
    /// held 93 items, the account's name a greyed-out header, not a submenu): from after the
    /// header to the next greyed-out item without a submenu whose title isn't one of the
    /// account's own top-level folders (that is the next account's header). A greyed-out
    /// folder of this account (the one the messages are in) stays in the section.
    static func section(after header: Int, in items: [Node], folders: Set<String>) -> [Node] {
        var section: [Node] = []
        for item in items.dropFirst(header + 1) {
            let looksLikeHeader = !item.isEnabled && !item.hasSubmenu && !item.title.isEmpty && indent(item) == 0
            if looksLikeHeader, !folders.contains(name(item)) { break }
            section.append(item)
        }
        return section
    }

    /// Opens each level, waits for its items, and presses the folder. Levels count from 1,
    /// the Message menu; `titles` is Message, Move to, the account, then each folder.
    /// `folders` is the account's own top-level folder names (to find where its section of a
    /// flat Move to list ends). `log` gets one line per level: its number, item count,
    /// submenu and enabled, the time; never a title. `anyOpen` asks the menu bar whether any
    /// of its menus shows.
    static func walk(_ titles: [[String]], bar: [Node], folders: Set<String>, anyOpen: () -> Bool, limits: Limits = Limits(), log: (String) -> Void) async -> Outcome {
        let clock = ContinuousClock()
        let started = clock.now
        func ms() -> Int { Int((clock.now - started) / .milliseconds(1)) }
        var opened: [Node] = []

        // Cancels every opened menu, deepest first; if the bar still shows one after 300 ms,
        // once more. The answer says whether the bar is closed.
        func cancelAll(_ reason: String) async -> Bool {
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
            return closed
        }
        func cancelled(_ reason: String) async -> Outcome { .cancelled(reason: reason, closed: await cancelAll(reason)) }

        func matches(_ wanted: [String], in items: [Node]) -> [Node] { items.filter { wanted.contains(name($0)) } }

        guard let first = titles.first, matches(first, in: bar).count == 1, let top = matches(first, in: bar).first else {
            log("menu: level 1 not found among \(bar.count) bar items, \(ms()) ms")
            return .cancelled(reason: "no Message menu", closed: true)
        }
        // Mail may answer a press late while its menu tracks, so a level counts as open when
        // its items show up within the level's time.
        _ = top.press()
        opened.append(top)
        var current = top
        // Set when the account is a header in a flat list: the next level is looked for
        // among that account's items only.
        var scope: [Node]?
        let accountLevel = 2
        for level in 1..<titles.count {
            let levelStart = clock.now
            var items = scope ?? current.items
            var found = matches(titles[level], in: items)
            while found.count != 1, scope == nil, clock.now - levelStart < limits.level, clock.now - started < limits.total {
                try? await Task.sleep(for: limits.poll)
                items = current.items
                found = matches(titles[level], in: items)
            }
            if level == accountLevel { log("menu: Move to holds \(shape(items))") }
            if let section = scope, !(found.count == 1 && found[0].hasSubmenu && level < titles.count - 1) {
                // A folder in a flat list: found by indentation, or by a name unique in the
                // account's section. Only a parent with a real submenu is opened instead.
                switch flatFind(Array(titles[level...]), in: section) {
                case .found(let index):
                    let folder = section[index]
                    log("menu: levels \(level + 1)-\(titles.count) found in the section by indentation or a unique name (\(describe(folder))), \(ms()) ms")
                    guard folder.isEnabled else { return .folderOff(closed: await cancelAll("the folder is greyed out")) }
                    let answered = folder.press()
                    log("menu: pressed the folder (\(answered ? "ok" : "no answer")), \(ms()) ms")
                    return .pressed
                case .twoOrMore:
                    return .ambiguous(closed: await cancelAll("the folder's name is in the section more than once"))
                case .notFound:
                    return await cancelled("levels \(level + 1)-\(titles.count) not found in the section")
                }
            }
            guard found.count == 1, let match = found.first else {
                return await cancelled("level \(level + 1) of \(titles.count): \(found.isEmpty ? "not found" : "\(found.count) matches") among \(items.count) items")
            }
            log("menu: level \(level + 1) of \(titles.count) found among \(items.count) items (\(describe(match))), \(ms()) ms")
            guard clock.now - started < limits.total else { return await cancelled("over the time limit") }
            let last = level == titles.count - 1
            if last {
                guard match.isEnabled else {
                    let closed = await cancelAll("level \(level + 1) of \(titles.count) is greyed out")
                    return .folderOff(closed: closed)
                }
                // The folder: Mail moves and closes its menus.
                let answered = match.press()
                log("menu: pressed the folder (\(answered ? "ok" : "no answer")), \(ms()) ms")
                return .pressed
            }
            if level == accountLevel, !match.hasSubmenu {
                // The account's name is a header in Move to's flat list: its folders follow it.
                guard let index = items.firstIndex(where: { titles[level].contains(name($0)) }) else {
                    return await cancelled("level \(level + 1): header not placed")
                }
                scope = section(after: index, in: items, folders: folders)
                log("menu: level \(level + 1) is a header; its section has \(scope!.count) items, \(scope!.filter(\.hasSubmenu).count) with submenus")
                continue
            }
            // A parent folder (or an account with a submenu): it must open; being greyed out
            // doesn't matter, only the final item is pressed.
            guard match.hasSubmenu else { return await cancelled("level \(level + 1) holds no submenu") }
            _ = match.press()
            opened.append(match)
            current = match
            scope = nil
        }
        return await cancelled("no folder level")
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

    var hasSubmenu: Bool { !AXMenuNode.childElements(element).isEmpty }

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
        let outcome = await MoveMenu.walk(titles, bar: bar, folders: MoveMenu.topFolders(of: mailbox.account), anyOpen: { bar.contains { $0.isOpen } }, log: KeysLog.note)
        switch outcome {
        case .folderOff(let closed):
            SnoozeLog.append(["move menu: the folder is greyed out, menu closed: \(closed ? "yes" : "no"), \(ms()) ms; nothing moved"], to: MailScript.logURL)
            return MailFiling.MoveReport(outcome: .notMoved, title: "Not moved",
                                         subtitle: closed ? "Mail greys out \(mailbox.shown) for this message; is it already there?" : "Mail's menu may still be open; press Esc")
        case .ambiguous(let closed):
            SnoozeLog.append(["move menu: two folders with that name in the account, menu closed: \(closed ? "yes" : "no"), \(ms()) ms; nothing moved"], to: MailScript.logURL)
            return MailFiling.MoveReport(outcome: .notMoved, title: "Not moved",
                                         subtitle: closed ? "Two folders named \(mailbox.chain.last ?? mailbox.shown); can't tell which in Mail's menu" : "Mail's menu may still be open; press Esc")
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
