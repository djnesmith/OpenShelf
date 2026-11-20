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
        "i": .favorite("Inbox"), "s": .favorite("Flagged"), "t": .favorite("Sent"), "d": .favorite("Drafts"), "a": .favorite("Archive"), "g": .firstMessage,
    ]

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
        return actsOnOneMessage(action)
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
        ("j / k", "next / previous message"), ("o", "open"), ("/", "search"),
        ("g i  g s  g t  g d  g a", "Inbox, Flagged, Sent, Drafts, Archive"),
        ("e  or  ]", "archive"), ("[", "archive, then the message above"), ("x", "move to Trash"),
        ("r / a / f", "reply / reply all / forward"), ("s", "flag"), ("b", "snooze"),
        ("v  or  l", "move to a mailbox"), ("m", "mute"), ("!", "junk"),
        ("⇧I / ⇧U", "mark read / unread"), ("z", "undo"), ("c", "new message"),
        ("* a", "select all"), ("Esc  or  * n", "select none (when several are selected)"), ("Esc", "close a message open in its own window"), ("u", "back to the list"), ("g g  /  G", "first / last message"), ("?", "this list"),
    ]
}
