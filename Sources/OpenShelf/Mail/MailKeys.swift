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
    /// `b` snooze, `c` compose, `?` the list. Not decided: `u`, `n`/`p`, `* n` (left out),
    /// `[` (archive, then the message above).
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
    ]

    static let afterG: [Character: Action] = [
        "i": .favorite("Inbox"), "s": .favorite("Flagged"), "t": .favorite("Sent"), "d": .favorite("Drafts"), "a": .favorite("Archive"),
    ]

    static let afterStar: [Character: Action] = ["a": .menu("Edit", "Select All")]

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
    static func mayTake(focusedRole: String?, isEditable: Bool, sendEnabled: Bool, modifiers: Modifiers, mailHasFocus: Bool = true) -> Bool {
        // A panel over Mail (Spotlight, Alfred) has the keys: never take them.
        guard mailHasFocus else { return false }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        guard !sendEnabled, !isEditable, let role = focusedRole else { return false }
        return listRoles.contains(role) || role == "AXWebArea"
    }

    static let listRoles: Set<String> = ["AXTable", "AXOutline", "AXRow", "AXCell"]

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
        ("* a", "select all"), ("?", "this list"),
    ]
}
