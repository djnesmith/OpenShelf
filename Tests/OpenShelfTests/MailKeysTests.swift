import Foundation
import Testing
@testable import OpenShelf

/// The single-key layer's rules. The tap itself is never installed here.
@MainActor
struct MailKeysTests {
    @Test func davidsKeys() {
        #expect(MailKeys.outcome(for: "x", pending: nil) == .act(.menu("Edit", "Delete")))
        #expect(MailKeys.outcome(for: "e", pending: nil) == .act(.menu("Message", "Archive")))
        #expect(MailKeys.outcome(for: "v", pending: nil) == .act(.file))
        #expect(MailKeys.outcome(for: "l", pending: nil) == .act(.file))
        #expect(MailKeys.outcome(for: "b", pending: nil) == .act(.snooze))
        #expect(MailKeys.outcome(for: "c", pending: nil) == .act(.menu("File", "New Message")))
        #expect(MailKeys.outcome(for: "?", pending: nil) == .act(.showKeys))
        #expect(MailKeys.outcome(for: "j", pending: nil) == .act(.nextMessage))
        #expect(MailKeys.outcome(for: "[", pending: nil) == .act(.archiveThenPrevious))
        #expect(MailKeys.outcome(for: "I", pending: nil) == .act(.menu("Message", "Mark as Read")))
        // Not decided, so left out: u, n, p, # and anything else.
        for key: Character in ["u", "n", "p", "#", "q", "1", " "] {
            #expect(MailKeys.outcome(for: key, pending: nil) == .pass, "\(key)")
        }
    }

    @Test func prefixes() {
        #expect(MailKeys.outcome(for: "g", pending: nil) == .prefix("g"))
        #expect(MailKeys.outcome(for: "i", pending: "g") == .act(.favorite("Inbox")))
        #expect(MailKeys.outcome(for: "a", pending: "g") == .act(.favorite("Archive")))
        #expect(MailKeys.outcome(for: "*", pending: nil) == .prefix("*"))
        #expect(MailKeys.outcome(for: "a", pending: "*") == .act(.menu("Edit", "Select All")))
        // A second key that means nothing after the prefix goes to Mail; "* n" is left out.
        #expect(MailKeys.outcome(for: "q", pending: "g") == .pass)
        #expect(MailKeys.outcome(for: "n", pending: "*") == .pass)
    }

    /// Fail open: only the message list or a message being read, no modifier but ⇧, nothing editable.
    @Test func takesKeysOnlyInTheListOrAMessageBeingRead() {
        func may(_ role: String?, editable: Bool = false, send: Bool = false, _ modifiers: MailKeys.Modifiers = []) -> Bool {
            MailKeys.mayTake(focusedRole: role, isEditable: editable, sendEnabled: send, modifiers: modifiers)
        }
        #expect(may("AXTable"))
        #expect(may("AXOutline"))
        #expect(may("AXRow", .shift))
        #expect(may("AXWebArea"))
        #expect(!may("AXWebArea", send: true))
        #expect(!may("AXWebArea", editable: true))
        #expect(!may("AXTextField"))
        #expect(!may("AXTextArea"))
        #expect(!may("AXButton"))
        #expect(!may(nil))
        #expect(!may("AXTable", [.other]))
        #expect(!may("AXTable", [.shift, .other]))
        // A panel over Mail (Spotlight, Alfred) has the keys.
        #expect(!MailKeys.mayTake(focusedRole: "AXTable", isEditable: false, sendEnabled: false, modifiers: [], mailHasFocus: false))
    }

    @Test func jAndKStopAtTheEnds() {
        #expect(MailKeys.row(after: nil, by: 1, count: 5) == 0)
        #expect(MailKeys.row(after: 2, by: 1, count: 5) == 3)
        #expect(MailKeys.row(after: 4, by: 1, count: 5) == 4)
        #expect(MailKeys.row(after: 0, by: -1, count: 5) == 0)
    }

    /// Items are found anywhere under their top menu (Mark › Unread, Find › Mailbox Search),
    /// and favorites only inside Go to Favorite Mailbox.
    @Test func findsItemsInSubmenus() {
        typealias Item = MailMenuTests.FakeItem
        let bar: [MenuNode] = [
            Item("Edit", [Item("Find", [Item("Mailbox Search")]), Item("Delete")]),
            Item("Mailbox", [Item("Inbox Only"), Item("Go to Favorite Mailbox", [Item("Inbox"), Item("Sent")])]),
            Item("Message", [Item("Mark", [Item("Mark as Read"), Item("Unread")])]),
        ]
        #expect(MailKeyActions.item("Mailbox Search", under: "Edit", in: bar)?.title == "Mailbox Search")
        #expect(MailKeyActions.item("Unread", under: "Message", in: bar)?.title == "Unread")
        #expect(MailKeyActions.item("Inbox", under: "Mailbox", within: "Go to Favorite Mailbox", in: bar)?.title == "Inbox")
        #expect(MailKeyActions.item("Drafts", under: "Mailbox", within: "Go to Favorite Mailbox", in: bar) == nil)
        #expect(MailKeyActions.item("Delete", under: "Message", in: bar) == nil)
    }

    @Test func offByDefault() {
        #expect(UserDefaults(suiteName: "OpenShelfTests.keys.\(UUID())")!.bool(forKey: MailKeyTap.enabledKey) == false)
        #expect(MailKeys.help.count >= 15)
    }
}
