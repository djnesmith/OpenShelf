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
        // Left out: n, p, # and anything else (u is back to the list since 2026-11-20).
        for key: Character in ["n", "p", "#", "q", "1", " "] {
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

    /// Esc closes a message open in its own window; never the viewer, a message being
    /// written, a sheet or popover, a field, or with Send on (David, 2026-11-20).
    @Test func escapeClosesOnlyAMessageWindow() {
        typealias F = MailKeys.WindowFacts
        let message = F(isStandardWindow: true, isViewer: false, hasSheetOrPopover: false, hasComposeControls: false, textFieldCount: 0)
        func may(_ window: F?, role: String? = "AXWebArea", editable: Bool = false, send: Bool = false,
                 _ modifiers: MailKeys.Modifiers = [], focus: Bool = true) -> Bool {
            MailKeys.mayCloseWithEscape(window, focusedRole: role, isEditable: editable, sendEnabled: send, modifiers: modifiers, mailHasFocus: focus)
        }
        #expect(may(message))
        #expect(may(message, role: "AXGroup"))
        var viewer = message; viewer.isViewer = true
        #expect(!may(viewer))
        // A message being written, as Check Mail saw one: Send, From, To/Cc/Subject fields.
        var compose = message; compose.hasComposeControls = true; compose.textFieldCount = 3
        #expect(!may(compose))
        // A Send button alone (fields nested out of reach) is enough to leave it alone.
        var sendOnly = message; sendOnly.hasComposeControls = true
        #expect(!may(sendOnly))
        var fieldsOnly = message; fieldsOnly.textFieldCount = 1
        #expect(!may(fieldsOnly))
        var sheet = message; sheet.hasSheetOrPopover = true
        #expect(!may(sheet))
        var panel = message; panel.isStandardWindow = false
        #expect(!may(panel))
        #expect(!may(nil))
        #expect(!may(message, editable: true))
        #expect(!may(message, send: true))
        #expect(!may(message, role: "AXTextField"))
        #expect(!may(message, role: "AXSearchField"))
        #expect(!may(message, .other))
        #expect(!may(message, .shift))
        #expect(!may(message, focus: false))
        #expect(MailKeys.help.contains { $0.0 == "Esc" && $0.1.contains("close") })
    }

    final class Node: DialogNode {
        let role: String
        let title: String? = nil
        let identifier: String?
        let children: [DialogNode]
        let date: Date? = nil
        init(_ role: String, id: String? = nil, _ children: [DialogNode] = []) {
            self.role = role
            identifier = id
            self.children = children
        }
        func setDate(_ date: Date) -> Bool { false }
        func press() -> Bool { false }
    }

    /// Mail's viewer as Check Mail saw it (2026-11-20): the mailbox sidebar's outline comes
    /// first; the message list is in "Main Window Preview Pane Vertical".
    @MainActor @Test func findsTheMessageListNotTheSidebar() {
        let list = Node("AXTable")
        let viewer = Node("AXWindow", id: "Mail.messageViewer.window.1", [
            Node("AXSplitGroup", id: "Main Window", [
                Node("AXScrollArea", [Node("AXOutline")]),
                Node("AXStaticText"), Node("AXSplitter"),
                Node("AXSplitGroup", id: "Main Window Preview Pane Vertical", [
                    Node("AXScrollArea", [list]), Node("AXSplitter"), Node("AXGroup"),
                    Node("AXScrollArea", [Node("AXWebArea", [Node("AXTable")])]),
                ]),
            ]),
            Node("AXToolbar"),
        ])
        #expect(MailKeys.messageList(in: viewer) as? Node === list)
        #expect(MailKeys.messageList(in: Node("AXWindow", id: "_NS:41", [Node("AXTable")])) == nil)
    }

    /// `u`: a message window closes, the viewer's reading pane gives the list the keyboard,
    /// the list itself does nothing; a message being written or a sheet: nothing.
    @Test func backToListInEachState() {
        typealias F = MailKeys.WindowFacts
        let message = F(isStandardWindow: true, isViewer: false, hasSheetOrPopover: false, hasComposeControls: false, textFieldCount: 0)
        var viewer = message; viewer.isViewer = true
        var compose = message; compose.hasComposeControls = true; compose.textFieldCount = 3
        var sheet = viewer; sheet.hasSheetOrPopover = true
        #expect(MailKeys.backToList(message, focusInList: false, sendEnabled: false) == .close)
        #expect(MailKeys.backToList(viewer, focusInList: false, sendEnabled: false) == .focusList)
        #expect(MailKeys.backToList(viewer, focusInList: true, sendEnabled: false) == .nothing)
        #expect(MailKeys.backToList(compose, focusInList: false, sendEnabled: false) == .nothing)
        #expect(MailKeys.backToList(message, focusInList: false, sendEnabled: true) == .nothing)
        #expect(MailKeys.backToList(sheet, focusInList: false, sendEnabled: false) == .nothing)
        #expect(MailKeys.backToList(nil, focusInList: false, sendEnabled: false) == .nothing)
    }

    /// u, g g and G are in the table and the list; g g and G only act from the list.
    @Test func uAndFirstAndLast() {
        #expect(MailKeys.outcome(for: "u", pending: nil) == .act(.backToList))
        #expect(MailKeys.outcome(for: "g", pending: "g") == .act(.firstMessage))
        #expect(MailKeys.outcome(for: "G", pending: nil) == .act(.lastMessage))
        #expect(MailKeys.outcome(for: "g", pending: nil) == .prefix("g"))
        #expect(MailKeys.actsOnOneMessage(.backToList))
        #expect(!MailKeys.actsOnOneMessage(.firstMessage))
        #expect(!MailKeys.actsOnOneMessage(.lastMessage))
        #expect(MailKeys.help.contains { $0.0 == "u" })
        #expect(MailKeys.help.contains { $0.0.contains("g g") && $0.0.contains("G") })
    }

    /// In a message open on its own, the keys that act on one message are taken; moving,
    /// mailboxes and anything editable, a field or Send on are not (2026-11-20).
    @Test func oneMessageKeysInAMessageWindow() {
        func may(_ role: String?, _ action: MailKeys.Action?, editable: Bool = false, send: Bool = false) -> Bool {
            MailKeys.mayTake(focusedRole: role, isEditable: editable, sendEnabled: send, modifiers: [], inMessageWindow: true, action: action)
        }
        for action in [MailKeys.Action.menu("Message", "Reply"), .menu("Message", "Reply All"), .menu("Message", "Forward"),
                       .menu("Message", "Archive"), .menu("Edit", "Delete"), .menu("Message", "Toggle Flag"), .snooze, .file,
                       .menu("Message", "Mute"), .menu("Message", "Move to Junk"), .menu("Message", "Unread"), .backToList, .showKeys] {
            #expect(may("AXWebArea", action), "\(action)")
            #expect(may("AXGroup", action), "\(action)")
        }
        // j/k: Mail has no next-message command in a message window, so they go to Mail.
        #expect(!may("AXWebArea", .nextMessage))
        #expect(!may("AXWebArea", .favorite("Inbox")))
        #expect(!may("AXWebArea", .firstMessage))
        #expect(!may("AXWebArea", nil))
        #expect(!may("AXWebArea", .menu("Message", "Reply"), editable: true))
        #expect(!may("AXWebArea", .menu("Message", "Reply"), send: true))
        #expect(!may("AXTextField", .menu("Message", "Reply")))
    }

    /// e and x in a message window act through the list only when the window was opened by
    /// `o` and the list's selection is still exactly the Message-IDs selected then. No
    /// subject plays any part. Nothing here touches real mail.
    @Test func conversationPlanByMessageID() {
        let opened: Set<String> = ["a@x", "b@x", "c@x"]
        // Bound and equal.
        #expect(MailKeys.conversationPlan(bound: opened, selectedRows: 1, current: opened) == .viaList(messages: 3))
        #expect(MailKeys.conversationPlan(bound: ["a@x"], selectedRows: 1, current: ["a@x"]) == .viaList(messages: 1))
        // The regression: he clicked another row with the same subject (a daily alert): other ids.
        #expect(MailKeys.conversationPlan(bound: ["alert-mon@x"], selectedRows: 1, current: ["alert-tue@x"]) == .thisMessage)
        // Unbound (opened by double-click, from search, before launch).
        #expect(MailKeys.conversationPlan(bound: nil, selectedRows: 1, current: opened) == .thisMessage)
        // Nothing selected now, or nothing bound.
        #expect(MailKeys.conversationPlan(bound: opened, selectedRows: 1, current: []) == .thisMessage)
        #expect(MailKeys.conversationPlan(bound: [], selectedRows: 1, current: []) == .thisMessage)
        // Overlapping but not equal: a message came or went.
        #expect(MailKeys.conversationPlan(bound: opened, selectedRows: 1, current: ["a@x", "b@x"]) == .thisMessage)
        #expect(MailKeys.conversationPlan(bound: opened, selectedRows: 1, current: opened.union(["d@x"])) == .thisMessage)
        // Two rows selected.
        #expect(MailKeys.conversationPlan(bound: opened, selectedRows: 2, current: opened) == .thisMessage)
    }
}
