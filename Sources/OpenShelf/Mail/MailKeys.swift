import Foundation

/// Gmail-style single keys for Mail (ROADMAP I5 table, MAIL-PLAN slice E), as pure rules:
/// which key does what, the `g` and `*` prefixes, and when a key must go to Mail untouched.
enum MailKeys {
    enum Action: Equatable, Sendable {
        /// A Mail menu item: the menu bar title it is under, then its own title.
        case menu(String, String)
        /// Go to Favorite Mailbox › the mailbox with this name.
        case favorite(String)
        case nextMessage, previousMessage
        case snooze, file, showKeys
        /// Archive, then the message above (Mail moves to the one below by itself).
        case archiveThenPrevious
        /// Esc and `* n`: select none. Only the list's selection changes, never a message.
        case clearSelection
        /// `u`: back to the list (David, 2026-11-20: "i like a back to the list hotkey"): a
        /// message open on its own closes; in the viewer, the keyboard goes to the list.
        case backToList
        /// `g g` and `G`: the first or last message in the list.
        case firstMessage, lastMessage
    }

    /// What a key press means, given a pending prefix.
    enum Outcome: Equatable, Sendable {
        /// Not ours: the key goes to Mail.
        case pass
        /// The first key of a two-key command; wait for the next one.
        case prefix(Character)
        case act(Action)
    }

    /// David's set (2026-11-19): Gmail's keys, `x` is Trash, `v` and `l` the mailbox picker,
    /// `b` snooze, `c` compose, `?` the list, `u` back to the list. Left out: `n`/`p`. `[
    /// (archive, then the message above). Esc and `* n` select none (David, 2026-11-20).
    static let single: [Character: Action] = [
        "j": .nextMessage, "k": .previousMessage,
        "o": .menu("Message", "Open Message"),
        "/": .menu("Edit", "Mailbox Search"),
        "e": .menu("Message", "Archive"), "]": .menu("Message", "Archive"), "[": .archiveThenPrevious,
        "x": .menu("Edit", "Delete"),
        "r": .menu("Message", "Reply"), "a": .menu("Message", "Reply All"), "f": .menu("Message", "Forward"),
        "s": .menu("Message", "Toggle Flag"),
        "b": .snooze, "v": .file, "l": .file,
        "m": .menu("Message", "Mute"),
        "!": .menu("Message", "Move to Junk"),
        "I": .menu("Message", "Mark as Read"), "U": .menu("Message", "Unread"),
        "z": .menu("Edit", "Undo"),
        "c": .menu("File", "New Message"),
        "?": .showKeys,
        "u": .backToList,
        "G": .lastMessage,
        escape: .clearSelection,
    ]

    static let escape: Character = "\u{1b}"

    static let afterG: [Character: Action] = [
        // David, 2026-11-20: g f Flagged, g s All Sent, g t All Trash (not Gmail's letters).
        "i": .favorite("Inbox"), "f": .favorite("Flagged"), "s": .favorite("Sent"), "t": .favorite("Trash"),
        // David, 2026-11-20: "\"g a\" should be \"All Mail\""; "there is no All Archive".
        // "but g A could go to Gmail's Archive folder": the sidebar's Archive row, found
        // as the old g a found it (keys.log 2026-11-21 00:57: "via sidebar").
        "d": .favorite("Drafts"), "a": .favorite(allMail), "A": .favorite("Archive"), "g": .firstMessage,
        // David, 2026-11-20: g j All Junk, g u Follow Up, g l Send Later, g r Remind Me.
        // "g T should go to Today" (David, 2026-11-20 evening): Mail's Today smart mailbox.
        "T": .favorite("Today"),
        "j": .favorite("Junk"), "u": .favorite("Follow Up"), "l": .favorite("Send Later"), "r": .favorite("Remind Me"),
    ]

    /// Gmail's All Mail: one per Gmail account, not a unified mailbox.
    static let allMail = "All Mail"

    enum AllMailResult: Equatable {
        /// Shown: the selected message's account's, or the first account that has one.
        case selected, first
        /// No account has a mailbox named All Mail.
        case none
        /// Mail's script failed or answered something else.
        case failed
    }

    static func allMailResult(_ text: String?) -> AllMailResult {
        switch text?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "#OK selected": .selected
        case "#OK first": .first
        case "#NONE": .none
        default: .failed
        }
    }

    /// ⌃N and ⌃P are j and k wherever j and k are taken (David, 2026-11-20: "Ctrl - n and
    /// Ctrl - p should work wherever j / k work"). `controlOnly`: ⌃ and no other modifier.
    /// Elsewhere (a text field, a message being written) the same rule as j and k passes
    /// them to Mail, where they are macOS's next and previous line.
    static func controlAlias(_ key: Character, controlOnly: Bool) -> Character? {
        guard controlOnly else { return nil }
        switch key {
        case "\u{0E}": return "j"
        case "\u{10}": return "k"
        default: return nil
        }
    }

    static let afterStar: [Character: Action] = ["a": .menu("Edit", "Select All"), "n": .clearSelection]

    /// How long a prefix waits for its second key.
    static let prefixTimeout: TimeInterval = 1

    static func outcome(for key: Character, pending: Character?) -> Outcome {
        switch pending {
        case "g": return afterG[key].map(Outcome.act) ?? .pass
        case "*": return afterStar[key].map(Outcome.act) ?? .pass
        default: break
        }
        if key == "g" || key == "*" { return .prefix(key) }
        return single[key].map(Outcome.act) ?? .pass
    }

    /// Whether a key may be taken from Mail at all. Fails open: anything unknown, any
    /// modifier but ⇧, or focus anywhere but the message list or a message being read
    /// (never a text field or a message being written) lets the key through.
    /// `inMessageViewer`: the focus is somewhere else in Mail's viewer window, such as one
    /// message of a conversation in the reading pane (David, 2026-11-20: r, a, f did
    /// nothing there). Only keys that act on one message are taken then.
    /// `inMessageWindow`: a message open in its own window (David, 2026-11-20: "r/a/f
    /// should work as well for an open message"): only the keys that act on one message.
    static func mayTake(focusedRole: String?, isEditable: Bool, sendEnabled: Bool, modifiers: Modifiers, mailHasFocus: Bool = true,
                        inMessageViewer: Bool = false, inMessageWindow: Bool = false, action: Action? = nil) -> Bool {
        // A panel over Mail (Spotlight, Alfred) has the keys: never take them.
        guard mailHasFocus else { return false }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        guard !sendEnabled, !isEditable, let role = focusedRole else { return false }
        if inMessageWindow {
            guard !textRoles.contains(role), let action else { return false }
            return actsOnOneMessage(action)
        }
        if listRoles.contains(role) || role == "AXWebArea" { return true }
        guard inMessageViewer, !textRoles.contains(role), let action else { return false }
        // j/k from a message of a conversation in the reading pane move the viewer's list
        // (David, 2026-11-20: "j / k and Ctrl n / Ctrl p should work to move down and up for
        // messages when a conversation's message is selected").
        return actsOnOneMessage(action) || action == .nextMessage || action == .previousMessage
    }

    /// Whether Mail's Send counts as on: its own state; missing (no message being written)
    /// is off; menus that can't be read are on, so keys fail open.
    static func sendIsOn(menuRead: Bool, send: Bool?) -> Bool {
        guard menuRead else { return true }
        return send ?? false
    }

    /// Roles that take typing, wherever they are.
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Keys that act on the selected message through Mail's own menu, as Mail's menu does
    /// for a message focused in a conversation.
    static func actsOnOneMessage(_ action: Action) -> Bool {
        switch action {
        case .menu(let top, let title): top == "Message" && title != "Open Message" || (top == "Edit" && title == "Delete")
        case .snooze, .file, .archiveThenPrevious, .showKeys, .backToList: true
        case .favorite, .nextMessage, .previousMessage, .clearSelection, .firstMessage, .lastMessage: false
        }
    }

    static let listRoles: Set<String> = ["AXTable", "AXOutline", "AXRow", "AXCell"]

    /// Esc is taken only to clear a selection of several messages in the list, with no
    /// sheet or popover open. Otherwise it goes to Mail, which uses it to close things.
    static func mayTakeEscape(focusedRole: String?, selectedCount: Int, hasSheetOrPopover: Bool, modifiers: Modifiers, mailHasFocus: Bool) -> Bool {
        guard mailHasFocus, modifiers.isEmpty, !hasSheetOrPopover, let role = focusedRole else { return false }
        return listRoles.contains(role) && selectedCount > 1
    }

    /// What the Esc-closes-a-message rule reads about Mail's front window.
    struct WindowFacts: Equatable {
        var isStandardWindow: Bool
        /// The main viewer (id "Mail.messageViewer.window…"), where Esc keeps its meaning.
        var isViewer: Bool
        var hasSheetOrPopover: Bool
        /// What a message being written has and a message being read hasn't (David's Check
        /// Mail, 2026-11-20): a Send button (id "send"), the From pop-up (id "popup_from"),
        /// and text fields for To, Cc and Subject.
        var hasComposeControls: Bool
        var textFieldCount: Int
    }

    /// Esc closes a message opened in a window of its own (David, 2026-11-20: "i also want
    /// ESC on a message to close it"): never the viewer, a message being written, with a
    /// sheet or popover open, in anything editable, or with Send enabled.
    static func mayCloseWithEscape(_ window: WindowFacts?, focusedRole: String?, isEditable: Bool, sendEnabled: Bool, modifiers: Modifiers, mailHasFocus: Bool) -> Bool {
        guard mailHasFocus, modifiers.isEmpty, let window, window.isStandardWindow, !window.isViewer else { return false }
        guard !window.hasSheetOrPopover, !window.hasComposeControls, window.textFieldCount == 0 else { return false }
        guard !isEditable, !sendEnabled, !textRoles.contains(focusedRole ?? "") else { return false }
        return true
    }

    /// Whether `window` is Mail's main viewer. A message open in its own window has the same
    /// identifier prefix ("Mail.messageViewer.window.39" beside the viewer's ".1", David's
    /// Check Mail, 2026-11-20); only the viewer has the "Main Window" split group.
    @MainActor
    static func isMainViewer(_ window: DialogNode) -> Bool {
        guard window.identifier?.hasPrefix("Mail.messageViewer.window") == true else { return false }
        return window.children.contains { $0.role == "AXSplitGroup" && $0.identifier == "Main Window" }
    }

    /// The titles Mail gives a unified mailbox: "All Inboxes" with several accounts, "Inbox"
    /// with one (David, 2026-11-20: "g i should go to \"All Inboxes\"").
    static func unifiedTitles(for name: String) -> [String] {
        switch name {
        case "Inbox": ["All Inboxes", "Inbox"]
        case "Flagged": ["Flagged", "All Flagged"]
        case "Sent": ["All Sent", "Sent"]
        case "Trash": ["All Trash", "Trash"]
        case "Drafts": ["All Drafts", "Drafts"]
        // Mail's own titles (MailFramework.loctable JunkSpecialMailboxName; Localizable and
        // TableHeaderContextMenu for the others); these have no "All" form.
        case "Junk": ["All Junk", "Junk"]
        default: [name]
        }
    }

    /// The first of `titles` (menu items or sidebar rows, as Mail shows them now) that is
    /// the unified mailbox `name`; a count after the name ("All Inboxes (12)") is ignored.
    static func unifiedIndex(for name: String, in titles: [String]) -> Int? {
        let clean = titles.map { $0.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression) }
        for wanted in unifiedTitles(for: name) {
            if let index = clean.firstIndex(of: wanted) { return index }
        }
        return nil
    }

    /// Whether the viewer's title says it is showing the unified mailbox `name`.
    static func showsUnified(_ name: String, windowTitle: String?) -> Bool {
        guard let windowTitle else { return false }
        return unifiedTitles(for: name).contains { windowTitle == $0 || windowTitle.hasPrefix($0 + " ") || windowTitle.hasPrefix($0 + " –") }
    }

    /// The message list in Mail's viewer window: the first table or outline inside the split
    /// group "Main Window Preview Pane Vertical" (David's Check Mail, 2026-11-20). The
    /// mailbox sidebar's outline comes first in the window, so the plain first table is wrong.
    @MainActor
    static func messageList(in window: DialogNode) -> DialogNode? {
        guard window.identifier?.hasPrefix("Mail.messageViewer.window") == true else { return nil }
        func pane(_ node: DialogNode, depth: Int) -> DialogNode? {
            guard depth < 4 else { return nil }
            for child in node.children where child.role == "AXSplitGroup" {
                if child.identifier == "Main Window Preview Pane Vertical" { return child }
                if let found = pane(child, depth: depth + 1) { return found }
            }
            return nil
        }
        func table(_ node: DialogNode, depth: Int) -> DialogNode? {
            guard depth < 6 else { return nil }
            for child in node.children {
                if ["AXTable", "AXOutline"].contains(child.role) { return child }
                if child.role == "AXWebArea" { continue }
                if let found = table(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return pane(window, depth: 0).flatMap { table($0, depth: 0) }
    }

    /// What `u` does: close a message open on its own, give the list the keyboard in the
    /// viewer, or nothing when the list has it already (or anything is unsure).
    enum BackToList: Equatable { case close, focusList, nothing }

    /// Whether `focused` is `list` or inside it, up to 8 levels. The sidebar is an outline
    /// too, so a list role alone doesn't say focus is in the message list (David,
    /// 2026-11-20: "when a folder is selected pressing u does not go back to the message list").
    static func isInside<T>(_ focused: T?, _ list: T?, parent: (T) -> T?, same: (T, T) -> Bool) -> Bool {
        guard let list else { return false }
        var node = focused
        for _ in 0..<8 {
            guard let current = node else { return false }
            if same(current, list) { return true }
            node = parent(current)
        }
        return false
    }

    static func backToList(_ window: WindowFacts?, focusInList: Bool, sendEnabled: Bool) -> BackToList {
        guard let window, !window.hasSheetOrPopover else { return .nothing }
        if window.isViewer { return focusInList ? .nothing : .focusList }
        return mayCloseWithEscape(window, focusedRole: nil, isEditable: false, sendEnabled: sendEnabled, modifiers: [], mailHasFocus: true) ? .close : .nothing
    }

    /// How `e` or `x` in a message window acts (David, 2026-11-20: "whatever e and x do when
    /// a message is selected in the list").
    enum ConversationPlan: Equatable {
        /// The viewer's selection is still exactly what was selected when this window was
        /// opened: close the window and press Archive or Delete in the viewer, so Mail does
        /// what it does for that row.
        case viaList(messages: Int)
        /// Anything else: Archive or Delete on the open message only.
        case thisMessage
    }

    /// By Message-ID only, never by subject: `bound` is the selection's Message-IDs taken
    /// when OpenShelf's `o` opened the window (nil when the window wasn't opened that way),
    /// `current` the selection's Message-IDs now. Same-subject digests and alerts make any
    /// subject check unsafe.
    static func conversationPlan(bound: Set<String>?, selectedRows: Int, current: Set<String>) -> ConversationPlan {
        guard let bound, !bound.isEmpty, selectedRows == 1, bound == current else { return .thisMessage }
        return .viaList(messages: current.count)
    }

    /// Whether Archive or Delete may be pressed in the viewer after the message window was
    /// closed, from what the elements show then, never from the close press's answer: the
    /// message window is gone, the window in front is the main viewer, and its selection is
    /// still exactly the Message-IDs bound at `o` (2026-11-20).
    static func mayPressInViewer(messageWindowGone: Bool, frontIsMainViewer: Bool, bound: Set<String>?, current: Set<String>) -> Bool {
        guard messageWindowGone, frontIsMainViewer, let bound, !bound.isEmpty else { return false }
        return bound == current
    }

    /// The button named `title` in the window's toolbar, at any depth (David's capture: the
    /// toolbar holds an AXGroup with the segments Archive, Delete and Junk).
    @MainActor
    static func toolbarButton(_ title: String, in window: DialogNode) -> DialogNode? {
        guard let toolbar = window.children.first(where: { $0.role == "AXToolbar" }) else { return nil }
        func find(_ node: DialogNode, depth: Int) -> DialogNode? {
            guard depth < 5 else { return nil }
            for child in node.children {
                if child.role == "AXButton", child.label == title { return child }
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return find(toolbar, depth: 0)
    }

    /// What pressing the open message's own Archive or Delete button came to.
    enum OpenMessageResult: Equatable {
        case noButton
        /// The window went away: the message was archived or trashed.
        case done
        /// Pressed (Accessibility may answer an error while Mail acts), but the window is
        /// still open: not claimed either way.
        case unsure
    }

    static func openMessageResult(buttonFound: Bool, windowGone: Bool) -> OpenMessageResult {
        guard buttonFound else { return .noButton }
        return windowGone ? .done : .unsure
    }

    // MARK: Verified actions (2026-11-20: Message › Archive "pressed" and nothing happened)

    /// Ways to make Mail do a command, tried in this order until Mail shows a change.
    enum ActionRoute: Equatable {
        /// The main viewer's own toolbar button (Archive, Delete, Junk).
        case toolbar
        /// The message list gets the keyboard first, then the menu item is pressed.
        case listThenMenu
    }

    enum ActionStep: Equatable {
        case attempt(ActionRoute)
        case done(ActionRoute)
        /// Something moved but the command isn't proven; no second route, to be safe.
        case unsure(ActionRoute)
        case gaveUp
    }

    /// What a try came to, read from Mail.
    enum ActionOutcome: Equatable {
        /// The command is proven (the messages left the list; the flag or read state changed
        /// on the same messages).
        case changed
        /// Mail looks exactly as before: the next route may try.
        case unchanged
        /// Mail changed, but not in a way that proves the command (the selection moved with
        /// the same rows; 2026-11-20: 9 selected became 1 and nothing was archived).
        case ambiguous
    }

    /// The next step: done after a proven change; stop, unsure, after an ambiguous one
    /// (a second route could act on the next message); after no change, the next route not
    /// yet tried, else give up.
    static func nextActionStep(tried: [ActionRoute], last: ActionOutcome?, toolbarAvailable: Bool) -> ActionStep {
        if let route = tried.last {
            switch last {
            case .changed?: return .done(route)
            case .ambiguous?: return .unsure(route)
            case .unchanged?, nil: break
            }
        }
        // The list first: Archive acts on the list's selection when the list has the
        // keyboard, as his own ⌘E does (2026-11-20: the toolbar press answered -25204 and
        // archived nothing). The toolbar button second.
        let order: [ActionRoute] = toolbarAvailable ? [.listThenMenu, .toolbar] : [.listThenMenu]
        guard let next = order.first(where: { !tried.contains($0) }) else { return .gaveUp }
        return .attempt(next)
    }

    /// What Mail shows before and after a command: the list's row count, the selected
    /// messages' ids, and their flag and read states.
    struct ListSnapshot: Equatable {
        var rows: Int
        var selected: Set<String>
        var flagged: [String: Bool] = [:]
        var read: [String: Bool] = [:]
    }

    /// How a command's effect shows in Mail.
    enum Verification: Equatable { case rowsLeave, flag, read, none }

    static func verification(for title: String) -> Verification {
        switch title {
        case "Archive", "Delete", "Move to Junk": .rowsLeave
        case "Toggle Flag", "Flag": .flag
        case "Mark as Read", "Unread", "Mark as Unread": .read
        default: .none
        }
    }

    /// The viewer's toolbar button for a command, where it has one.
    static func toolbarLabel(for title: String) -> String? {
        switch title {
        case "Archive": "Archive"
        case "Delete": "Delete"
        case "Move to Junk": "Junk"
        default: nil
        }
    }

    /// What a try came to. Archive, delete, junk: proven only when the list lost rows and
    /// none of the messages selected before is still selected. Flag and read: proven when the
    /// same messages are selected and their state changed. Anything else that moved is
    /// ambiguous; exactly as before is unchanged. Mute can't be seen and counts as changed.
    static func outcome(_ before: ListSnapshot, _ after: ListSnapshot, _ kind: Verification) -> ActionOutcome {
        if kind == .none { return .changed }
        guard !before.selected.isEmpty else { return after == before ? .unchanged : .ambiguous }
        switch kind {
        case .rowsLeave:
            if after.rows < before.rows, before.selected.isDisjoint(with: after.selected) { return .changed }
        case .flag:
            if after.selected == before.selected, after.flagged != before.flagged { return .changed }
        case .read:
            if after.selected == before.selected, after.read != before.read { return .changed }
        case .none:
            return .changed
        }
        return after == before ? .unchanged : .ambiguous
    }


    /// A window a key may close, as the close rule sees it. A protocol, so tests use a fake.
    @MainActor
    protocol ClosableWindow {
        /// Mail's main viewer: never closed by any key.
        var isMainViewer: Bool { get }
        /// Presses this window's own close button once; nil when it has none.
        func pressCloseButton() -> Bool?
    }

    enum Closed: Equatable {
        case pressed
        /// Accessibility answered an error; the window may well be closed (it goes away
        /// during the press), so nothing else is tried.
        case pressAnswered
        case noCloseButton
        case refusedMainViewer
    }

    /// Closes the captured message window with one press of its own close button, and does
    /// nothing else (2026-11-20: after an error from that press, a File › Close fallback
    /// closed the next front window, Mail's main viewer). No menu item and no front-window
    /// action is ever used here, and the main viewer is never closed.
    @MainActor
    static func closeOnce(_ window: ClosableWindow) -> Closed {
        guard !window.isMainViewer else { return .refusedMainViewer }
        switch window.pressCloseButton() {
        case nil: return .noCloseButton
        case true?: return .pressed
        case false?: return .pressAnswered
        }
    }

    /// A message list's selection, by row index. A protocol, so tests use a fake.
    @MainActor
    protocol SelectableList {
        var selectedRows: [Int] { get }
        /// The row with the keyboard focus, when one has it.
        var focusedRow: Int? { get }
        func select(_ rows: [Int]) -> Bool
    }

    enum Cleared: Equatable {
        case none
        /// Mail kept no empty selection; one row stays selected.
        case keptOne(Int)
        case refused
    }

    /// Selects none; if Mail won't have an empty selection, only the focused row (or the
    /// first selected one). Messages themselves are never touched.
    @MainActor
    static func clearSelection(_ list: SelectableList) -> Cleared {
        let before = list.selectedRows
        guard before.count > 1 else { return .refused }
        if list.select([]), list.selectedRows.isEmpty { return .none }
        let keep = list.focusedRow.flatMap { before.contains($0) ? $0 : nil } ?? before[0]
        if list.select([keep]), list.selectedRows == [keep] { return .keptOne(keep) }
        return .refused
    }

    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1)
        static let other = Modifiers(rawValue: 2)
    }

    /// The `?` list, one line a key, in the table's order.
    static let help: [(String, String)] = [
        ("j / k  or  ⌃N / ⌃P", "next / previous message"), ("o", "open"), ("/", "search"),
        ("g i  g f  g s  g t  g d  g a", "All Inboxes, Flagged, All Sent, All Trash, All Drafts, All Mail"),
        ("g A  g T  g j  g u  g l  g r", "Archive, Today, All Junk, Follow Up, Send Later, Remind Me"),
        ("e  or  ]", "archive"), ("[", "archive, then the message above"), ("x", "move to Trash"),
        ("r / a / f", "reply / reply all / forward"), ("s", "flag"), ("b", "snooze"),
        ("v  or  l", "move to a mailbox"), ("m", "mute"), ("!", "junk"),
        ("⇧I / ⇧U", "mark read / unread"), ("z", "undo"), ("c", "new message"),
        ("* a", "select all"), ("Esc  or  * n", "select none (when several are selected)"), ("Esc", "close a message open in its own window"), ("u", "back to the list"), ("g g  /  G", "first / last message"), ("?", "this list"),
    ]
}
