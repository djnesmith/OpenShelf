import CoreGraphics
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
        // A second key that means nothing after the prefix goes to Mail.
        #expect(MailKeys.outcome(for: "q", pending: "g") == .pass)
        #expect(MailKeys.outcome(for: "q", pending: "*") == .pass)
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
        // One message of a conversation focused in the viewer (2026-11-20): keys that act on
        // one message are taken; moving, mailboxes and anything editable or in a field are not.
        func inViewer(_ role: String?, _ action: MailKeys.Action?, editable: Bool = false, send: Bool = false) -> Bool {
            MailKeys.mayTake(focusedRole: role, isEditable: editable, sendEnabled: send, modifiers: [], inMessageViewer: true, action: action)
        }
        for action in [MailKeys.Action.menu("Message", "Reply"), .menu("Message", "Reply All"), .menu("Message", "Forward"),
                       .menu("Message", "Archive"), .menu("Edit", "Delete"), .menu("Message", "Toggle Flag"), .snooze, .file,
                       .menu("Message", "Move to Junk"), .menu("Message", "Mark as Read"), .archiveThenPrevious] {
            #expect(inViewer("AXGroup", action), "\(action)")
            #expect(inViewer("AXScrollArea", action), "\(action)")
        }
        #expect(!inViewer("AXGroup", .nextMessage))
        #expect(!inViewer("AXGroup", .favorite("Inbox")))
        #expect(!inViewer("AXGroup", .menu("Message", "Open Message")))
        #expect(!inViewer("AXGroup", nil))
        #expect(!inViewer("AXGroup", .menu("Message", "Reply"), editable: true))
        #expect(!inViewer("AXGroup", .menu("Message", "Reply"), send: true))
        #expect(!inViewer("AXTextField", .menu("Message", "Reply")))
        #expect(!inViewer("AXSearchField", .menu("Message", "Reply")))
        #expect(!MailKeys.mayTake(focusedRole: "AXGroup", isEditable: false, sendEnabled: false, modifiers: [], inMessageViewer: false, action: .menu("Message", "Reply")))
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

    /// While one of OpenShelf's own panels has the keyboard over Mail, the tap takes no
    /// key, so what is typed there arrives. `g` is a prefix: taken, with no action run.
    @MainActor @Test func keysPassWhileAnOpenShelfPanelHasTheKeyboard() {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: true)!
        var g: [UniChar] = Array("g".utf16)
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &g)
        let taken = MailKeyTap().takes(type: .keyDown, event: event, ownPanelHasKeyboard: false, focusAllows: { _, _ in true })
        #expect(taken)
        let passed = MailKeyTap().takes(type: .keyDown, event: event, ownPanelHasKeyboard: true, focusAllows: { _, _ in true })
        #expect(!passed)
    }

    /// Esc and `* n` mean select none.
    @Test func escapeAndStarNSelectNone() {
        #expect(MailKeys.outcome(for: MailKeys.escape, pending: nil) == .act(.clearSelection))
        #expect(MailKeys.outcome(for: "n", pending: "*") == .act(.clearSelection))
        #expect(MailKeys.outcome(for: MailKeys.escape, pending: "*") == .pass)
        #expect(MailKeys.help.contains { $0.0.contains("Esc") && $0.0.contains("* n") })
    }

    /// Esc is taken only for several selected messages in the list with nothing open over
    /// it; everywhere else Mail gets it (it closes things there).
    static let escapeCases: [(String?, Int, Bool, MailKeys.Modifiers, Bool, Bool)] = [
        ("AXTable", 2, false, [], true, true),
        ("AXRow", 40, false, [], true, true),
        ("AXOutline", 3, false, [], true, true),
        ("AXTable", 1, false, [], true, false),
        ("AXTable", 0, false, [], true, false),
        ("AXTable", 5, true, [], true, false),
        ("AXTable", 5, false, .shift, true, false),
        ("AXTable", 5, false, .other, true, false),
        ("AXTable", 5, false, [], false, false),
        ("AXTextField", 5, false, [], true, false),
        ("AXWebArea", 5, false, [], true, false),
        (nil, 5, false, [], true, false),
    ]

    @Test func escapeFailsOpen() {
        for (role, count, sheet, modifiers, focus, expected) in Self.escapeCases {
            #expect(MailKeys.mayTakeEscape(focusedRole: role, selectedCount: count, hasSheetOrPopover: sheet, modifiers: modifiers, mailHasFocus: focus) == expected,
                    "\(role ?? "nil") \(count) \(sheet)")
        }
    }

    @MainActor final class FakeList: MailKeys.SelectableList {
        var selectedRows: [Int]
        let focusedRow: Int?
        let allowsEmpty: Bool
        let allowsAny: Bool
        /// Answers yes but keeps the selection as it was (an empty one, or any).
        let quietlyKeepsEmpty: Bool
        let quietlyKeepsAll: Bool
        var calls: [[Int]] = []
        init(_ selected: [Int], focused: Int? = nil, allowsEmpty: Bool = true, allowsAny: Bool = true,
             quietlyKeepsEmpty: Bool = false, quietlyKeepsAll: Bool = false) {
            selectedRows = selected
            focusedRow = focused
            self.allowsEmpty = allowsEmpty
            self.allowsAny = allowsAny
            self.quietlyKeepsEmpty = quietlyKeepsEmpty
            self.quietlyKeepsAll = quietlyKeepsAll
        }
        func select(_ rows: [Int]) -> Bool {
            calls.append(rows)
            if quietlyKeepsAll || (rows.isEmpty && quietlyKeepsEmpty) { return true }
            guard allowsAny, !rows.isEmpty || allowsEmpty else { return false }
            selectedRows = rows
            return true
        }
    }

    @MainActor @Test func clearingSelectsNoneOrKeepsOneRow() {
        let empty = FakeList([0, 1, 2], focused: 1)
        #expect(MailKeys.clearSelection(empty) == .none)
        #expect(empty.selectedRows.isEmpty)
        // Mail refusing an empty selection: the focused row stays, else the first selected.
        let focused = FakeList([0, 1, 2], focused: 2, allowsEmpty: false)
        #expect(MailKeys.clearSelection(focused) == .keptOne(2))
        #expect(focused.selectedRows == [2])
        let outside = FakeList([3, 4], focused: 9, allowsEmpty: false)
        #expect(MailKeys.clearSelection(outside) == .keptOne(3))
        // Mail answering yes but keeping the selection is not taken at its word.
        let quietEmpty = FakeList([0, 1], focused: 1, quietlyKeepsEmpty: true)
        #expect(MailKeys.clearSelection(quietEmpty) == .keptOne(1))
        #expect(MailKeys.clearSelection(FakeList([0, 1], quietlyKeepsAll: true)) == .refused)
        let stubborn = FakeList([3, 4], allowsAny: false)
        #expect(MailKeys.clearSelection(stubborn) == .refused)
        #expect(stubborn.selectedRows == [3, 4])
        // One or no message selected: nothing is changed.
        let one = FakeList([5])
        #expect(MailKeys.clearSelection(one) == .refused)
        #expect(one.calls.isEmpty)
    }
}
