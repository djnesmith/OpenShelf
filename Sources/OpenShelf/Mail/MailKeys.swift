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
        /// ⇧U: read ↔ unread (David, 2026-11-20 evening: "I would rather have shift u be a
        /// toggle between unread and read"; "we can get rid of shift i").
        case toggleRead
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
        "U": .toggleRead,
        "z": .menu("Edit", "Undo"),
        "c": .menu("File", "New Message"),
        "?": .showKeys,
        // David, 2026-11-20 evening: "shouldn't u be undo?" (vim); back to the list is Esc now.
        "u": .menu("Edit", "Undo"),
        "G": .lastMessage,
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

    /// Mail's Undo item: titled after what it undoes ("Undo Archive", "Undo Move"), so
    /// "Undo" alone matched nothing (keys.log 2026-11-21 01:17: "no “Undo” in Mail's Edit
    /// menu"). The first item that is "Undo" or starts with "Undo ".
    static func undoIndex(in titles: [String]) -> Int? {
        titles.firstIndex { $0 == "Undo" || $0.hasPrefix("Undo ") }
    }

    /// A sidebar row's name: the first value of a static text or text field inside it (a
    /// smart mailbox such as Today shows its name in a text field, 2026-11-20: g T missed
    /// it), else the row's own title or description. Read 4 levels deep.
    static func sidebarLabel<T>(_ row: T, role: (T) -> String?, value: (T) -> String?, label: (T) -> String?, children: (T) -> [T]) -> String {
        func text(_ node: T, depth: Int) -> String? {
            if ["AXStaticText", "AXTextField"].contains(role(node) ?? ""), let found = value(node), !found.isEmpty { return found }
            guard depth < 4 else { return nil }
            for child in children(node) { if let found = text(child, depth: depth + 1) { return found } }
            return nil
        }
        return text(row, depth: 0) ?? label(row) ?? ""
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
                        inMessageViewer: Bool = false, inMessageWindow: Bool = false, action: Action? = nil, gPrefix: Bool = false) -> Bool {
        // A panel over Mail (Spotlight, Alfred) has the keys: never take them.
        guard mailHasFocus else { return false }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        guard !sendEnabled, !isEditable, let role = focusedRole else { return false }
        if inMessageWindow {
            guard !textRoles.contains(role), let action else { return false }
            return actsOnOneMessage(action)
        }
        if listRoles.contains(role) || role == "AXWebArea" { return true }
        guard inMessageViewer, !textRoles.contains(role) else { return false }
        // g and its second key work anywhere in the viewer: after a g key through the
        // sidebar focus sits on the window, and g passed to Mail, whose type-select then
        // took the T of g T (keys.log 2026-11-21 01:27:57, David: "g T sometimes just goes
        // down the list of messages").
        if gPrefix { return true }
        guard let action else { return false }
        switch action {
        case .favorite, .firstMessage, .lastMessage: return true
        default: break
        }
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
        case .snooze, .file, .archiveThenPrevious, .showKeys, .toggleRead: true
        case .favorite, .nextMessage, .previousMessage, .clearSelection, .firstMessage, .lastMessage: false
        }
    }

    static let listRoles: Set<String> = ["AXTable", "AXOutline", "AXRow", "AXCell"]

    /// What Esc does in Mail's viewer (David, 2026-11-20 evening: Esc takes over u's "back
    /// to the list"). A message open in its own window is closed before this is asked.
    enum EscapePlan: Equatable { case pass, focusList, clearSelection }

    /// In this order, the first that applies: anything editable, a text or search field, a
    /// sheet, popover or open menu, or a modifier: Mail gets Esc (it cancels them). Focus
    /// in the viewer outside its message list (the sidebar, the reading pane, the window
    /// after a g key): the list gets the keyboard. In the message list with several
    /// selected: select none. Anything else: Mail.
    static func escapePlan(focusedRole: String?, isEditable: Bool, inMessageList: Bool, inViewer: Bool, selectedCount: Int,
                           hasSheetOrPopover: Bool, menuOpen: Bool, modifiers: Modifiers, mailHasFocus: Bool) -> EscapePlan {
        guard mailHasFocus, modifiers.isEmpty, !hasSheetOrPopover, !menuOpen, let role = focusedRole else { return .pass }
        guard !isEditable, !textRoles.contains(role) else { return .pass }
        if inMessageList { return selectedCount > 1 ? .clearSelection : .pass }
        return inViewer ? .focusList : .pass
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

    /// ⇧U's item. Mail has one item it renames by state: "Mark as Read" on unread mail,
    /// "Mark as Unread" on read mail ("Unread" is only its nib name; keys.log 2026-11-21
    /// 01:50: "no “Unread” in Mail's Message menu"). Whichever Mail shows; nil for neither.
    static func toggleReadTitle(shows: (String) -> Bool) -> String? {
        ["Mark as Read", "Mark as Unread"].first(where: shows)
    }

    /// `e` or `x` in an inbox on a message whose reminder fired (David, 2026-11-21: "if i hit e on a
    /// message that has a Reminder in the inbox can it clear the reminder?"). Such a row is
    /// already in Archive, so Archive alone leaves it in the inbox. Only in an inbox: a
    /// snoozed message (Remind Me, then Archive) keeps its pending reminder wherever else
    /// `e` meets it. Nil (Archive exactly as before) without an enabled
    /// Message › Remind Me › Clear Reminder ("e for archived messages with no reminders
    /// remains the same").
    @MainActor
    static func reminderToClear(title: String, bar: [MenuNode], viewerShowsInbox: Bool, selected: Int) -> MenuNode? {
        guard ["Archive", "Delete"].contains(title), viewerShowsInbox, selected > 0,
              let item = MailMenu.find(MailMenu.clearReminder, in: bar), item.isEnabled else { return nil }
        return item
    }

    enum AfterClear: Equatable {
        /// Every selected row left the list: nothing left to archive.
        case done
        /// Mail still selects only messages that were selected before: archive those.
        case archive
        /// The selection moved to other messages: Archive now could act on them.
        case stop
    }

    /// `x` on a message whose reminder fired (David, 2026-11-21: "yeah x would need the same
    /// clear reminder"): Delete goes first, since a row the cleared reminder took out of the
    /// list can no longer be trashed from it; Clear Reminder second, only while Mail still
    /// selects nothing but messages selected before the Delete.
    static func mayClearAfterDelete(_ before: ListSnapshot, _ now: ListSnapshot) -> Bool {
        !now.selected.isEmpty && now.selected.isSubset(of: before.selected)
    }

    /// What to do after Clear Reminder, from the list before and after it.
    static func afterClearingReminder(_ before: ListSnapshot, _ after: ListSnapshot, selectedRows: Int) -> AfterClear {
        if !after.selected.isEmpty, after.selected.isSubset(of: before.selected) { return .archive }
        if selectedRows > 0, before.selected.isDisjoint(with: after.selected), before.rows - after.rows >= selectedRows { return .done }
        return .stop
    }

    /// The row to select after a snooze: the snoozed rows left, so the row that took the
    /// first one's place, else (they were last) the one above; the rows stayed, the row
    /// below them, else the one above. Nil for an empty list or nothing selected.
    static func rowAfterSnooze(selected: [Int], rowsBefore: Int, rowsAfter: Int) -> Int? {
        guard rowsAfter > 0, let first = selected.min(), let last = selected.max() else { return nil }
        if rowsAfter <= rowsBefore - selected.count { return min(first, rowsAfter - 1) }
        if last + 1 < rowsAfter { return last + 1 }
        return first > 0 ? first - 1 : nil
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
        ("e  or  ]", "archive (in an inbox, clears a fired reminder)"), ("[", "archive, then the message above"), ("x", "move to Trash (in an inbox, clears a fired reminder)"),
        ("r / a / f", "reply / reply all / forward"), ("s", "flag"), ("b", "snooze"),
        ("v  or  l", "move to a mailbox"), ("m", "mute"), ("!", "junk"),
("⇧U", "mark read / unread (toggles)"), ("u  or  z", "undo"), ("c", "new message"),
        ("* a", "select all"), ("* n", "select none"),
        ("Esc", "close a message window; else back to the list; in the list, select none (several selected)"), ("g g  /  G", "first / last message"), ("?", "this list"),
    ]
}
