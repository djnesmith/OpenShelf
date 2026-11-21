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
        #expect(MailKeys.outcome(for: "a", pending: "g") == .act(.favorite("All Mail")))
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
        // j/k from a message of a conversation move the viewer's list (2026-11-20).
        #expect(inViewer("AXGroup", .nextMessage))
        #expect(inViewer("AXGroup", .previousMessage))
        #expect(!inViewer("AXTextField", .nextMessage))
        #expect(!inViewer("AXGroup", .nextMessage, editable: true))
        // g keys anywhere in the viewer outside a field (focus on the window after a g key).
        #expect(inViewer("AXGroup", .favorite("Inbox")))
        #expect(inViewer("AXWindow", .favorite("Today")))
        #expect(inViewer("AXWindow", .firstMessage))
        #expect(MailKeys.mayTake(focusedRole: "AXWindow", isEditable: false, sendEnabled: false, modifiers: [], inMessageViewer: true, gPrefix: true))
        #expect(!MailKeys.mayTake(focusedRole: "AXTextField", isEditable: false, sendEnabled: false, modifiers: [], inMessageViewer: true, gPrefix: true))
        #expect(!MailKeys.mayTake(focusedRole: "AXWindow", isEditable: true, sendEnabled: false, modifiers: [], inMessageViewer: true, gPrefix: true))
        #expect(!MailKeys.mayTake(focusedRole: "AXWindow", isEditable: false, sendEnabled: false, modifiers: [], inMessageViewer: true))   // * stays in the list
        #expect(!inViewer("AXTextField", .favorite("Today")))
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

    /// ⌃N and ⌃P are j and k, checked as plain keys by the same focus rule; ⌃ with anything
    /// else, or other ⌃ keys, are not; ⌃N after g is j, not g j. focusAllows answers no here,
    /// so nothing reaches Mail.
    @Test func controlNAndPAreJAndK() {
        #expect(MailKeys.controlAlias("\u{0E}", controlOnly: true) == "j")
        #expect(MailKeys.controlAlias("\u{10}", controlOnly: true) == "k")
        #expect(MailKeys.controlAlias("\u{0E}", controlOnly: false) == nil)
        #expect(MailKeys.controlAlias("\u{01}", controlOnly: true) == nil)
        #expect(MailKeys.controlAlias("j", controlOnly: true) == nil)
        func press(_ char: String, _ flags: CGEventFlags, on tap: MailKeyTap) -> (MailKeys.Outcome?, CGEventFlags?) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: true)!
            var units = Array(char.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            event.flags = flags
            var seen: (MailKeys.Outcome?, CGEventFlags?) = (nil, nil)
            let taken = tap.takes(type: .keyDown, event: event, ownPanelHasKeyboard: false, focusAllows: { checked, outcome in
                seen = (outcome, checked.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]))
                return false
            })
            #expect(!taken)
            return seen
        }
        let tap = MailKeyTap()
        let n = press("\u{0E}", .maskControl, on: tap)
        #expect(n.0 == .act(.nextMessage))
        #expect(n.1 == [])
        #expect(press("\u{10}", .maskControl, on: tap).0 == .act(.previousMessage))
        // ⌃⌥N, ⌃⇧N: not j; they reach the rule as ⌃ keys, which pass.
        #expect(press("\u{0E}", [.maskControl, .maskAlternate], on: tap).0 == nil)
        #expect(press("\u{0E}", [.maskControl, .maskShift], on: tap).0 == nil)
        // g then ⌃N: the prefix is dropped, so it is j (next message), not g j (All Junk).
        _ = press("g", [], on: tap)
        #expect(press("\u{0E}", .maskControl, on: tap).0 == .act(.nextMessage))
    }

    /// The list j or k moves: the focused element's nearest list above it; none when
    /// focus is in the reading pane, so the viewer's list is used then.
    @Test func jAndKFindTheListAboveTheFocus() {
        final class N { let role: String; let parent: N?; init(_ role: String, _ parent: N?) { self.role = role; self.parent = parent } }
        let window = N("AXWindow", nil), list = N("AXOutline", window), row = N("AXRow", list), cell = N("AXCell", row)
        let pane = N("AXScrollArea", window), web = N("AXWebArea", pane)
        func above(_ start: N) -> N? { MailKeys.ancestor(of: start, parent: { $0.parent }, matching: { ["AXTable", "AXOutline"].contains($0.role) }) }
        #expect(above(cell) === list)
        #expect(above(list) === list)
        #expect(above(web) == nil)
        #expect(above(window) == nil)
    }

    /// A double-click binds the message window it opens only when it lands in the main
    /// viewer's message list; a click elsewhere, another window in front or an unreadable
    /// frame binds nothing, so e and x then act on the open message only.
    @Test func doubleClickBindsOnlyFromTheList() {
        let list = CGRect(x: 300, y: 100, width: 400, height: 600)   // top-left origin
        // On a 1000-point-high primary screen, y 800 from the bottom is 200 from the top.
        #expect(MailKeys.axPoint(fromCocoa: CGPoint(x: 350, y: 800), primaryHeight: 1000) == CGPoint(x: 350, y: 200))
        #expect(MailKeys.bindsAfterDoubleClick(viewerInFront: true, listFrame: list, point: CGPoint(x: 350, y: 200)))
        #expect(!MailKeys.bindsAfterDoubleClick(viewerInFront: true, listFrame: list, point: CGPoint(x: 100, y: 200)))   // the sidebar
        #expect(!MailKeys.bindsAfterDoubleClick(viewerInFront: true, listFrame: list, point: CGPoint(x: 350, y: 50)))    // the toolbar
        #expect(!MailKeys.bindsAfterDoubleClick(viewerInFront: false, listFrame: list, point: CGPoint(x: 350, y: 200)))
        #expect(!MailKeys.bindsAfterDoubleClick(viewerInFront: true, listFrame: nil, point: CGPoint(x: 350, y: 200)))
        #expect(!MailKeys.bindsAfterDoubleClick(viewerInFront: true, listFrame: .zero, point: .zero))
        // Bound, a double-clicked window gets the same whole-conversation plan as an o window.
        #expect(MailKeys.conversationPlan(bound: ["<a>", "<b>"], selectedRows: 1, current: ["<a>", "<b>"]) == .viaList(messages: 2))
        #expect(MailKeys.conversationPlan(bound: nil, selectedRows: 1, current: ["<a>", "<b>"]) == .thisMessage)
    }

    /// z finds Mail's Undo by its start: "Undo Archive", "Undo Move", plain "Undo"; never
    /// Redo or a word that only starts with Undo.
    @Test func undoIsFoundByItsStart() {
        #expect(MailKeys.undoIndex(in: ["Undo Archive", "Redo", "Cut"]) == 0)
        #expect(MailKeys.undoIndex(in: ["Redo Move", "Undo Move"]) == 1)
        #expect(MailKeys.undoIndex(in: ["Undo"]) == 0)
        #expect(MailKeys.undoIndex(in: ["Undone", "Redo"]) == nil)
        #expect(MailKeys.undoIndex(in: []) == nil)
        #expect(MailKeys.outcome(for: "z", pending: nil) == .act(.menu("Edit", "Undo")))
    }

    /// A sidebar row's name: a static text (Archive), or a text field (the smart mailbox
    /// Today under Smart Mailboxes, 2026-11-20), else the row's title; so g T finds Today.
    @Test func sidebarRowsReadTextFieldsToo() {
        final class N { let role: String; let value: String?; let title: String?; let kids: [N]
            init(_ role: String, value: String? = nil, title: String? = nil, _ kids: [N] = []) { self.role = role; self.value = value; self.title = title; self.kids = kids } }
        func name(_ row: N) -> String { MailKeys.sidebarLabel(row, role: { $0.role }, value: { $0.value }, label: { $0.title }, children: { $0.kids }) }
        let archive = N("AXRow", [N("AXCell", [N("AXImage"), N("AXStaticText", value: "Archive")])])
        let today = N("AXRow", [N("AXCell", [N("AXImage"), N("AXTextField", value: "Today")])])
        let header = N("AXRow", [N("AXCell", [N("AXStaticText", value: "Smart Mailboxes")])])
        let titled = N("AXRow", title: "Notes", [N("AXCell", [N("AXImage")])])
        let deep = N("AXRow", [N("AXCell", [N("AXGroup", [N("AXGroup", [N("AXTextField", value: "Deep")])])])])
        #expect(name(archive) == "Archive")
        #expect(name(today) == "Today")
        #expect(name(titled) == "Notes")
        #expect(name(deep) == "Deep")
        #expect(MailKeys.unifiedIndex(for: "Today", in: [archive, header, today].map(name)) == 2)
    }

    /// Esc and `* n` mean select none.
    @Test func escapeAndStarNSelectNone() {
        #expect(MailKeys.outcome(for: "n", pending: "*") == .act(.clearSelection))
        #expect(MailKeys.outcome(for: MailKeys.escape, pending: "*") == .pass)
        #expect(MailKeys.help.contains { $0.0 == "* n" })
        #expect(MailKeys.help.contains { $0.0 == "Esc" && $0.1.contains("back to the list") && $0.1.contains("select none") })
    }

    /// Esc in the viewer (David, 2026-11-20 evening), the first that applies: anything
    /// editable, a text or search field, a sheet, popover or open menu, a modifier, or Mail
    /// not focused: Mail gets it. Outside the message list in the viewer: back to the list.
    /// In the list: select none with several selected, else Mail.
    @Test func escapePlanInOrder() {
        func plan(_ role: String? = "AXOutline", editable: Bool = false, inList: Bool = false, inViewer: Bool = true, selected: Int = 0,
                  sheet: Bool = false, menu: Bool = false, modifiers: MailKeys.Modifiers = [], focus: Bool = true) -> MailKeys.EscapePlan {
            MailKeys.escapePlan(focusedRole: role, isEditable: editable, inMessageList: inList, inViewer: inViewer, selectedCount: selected,
                                hasSheetOrPopover: sheet, menuOpen: menu, modifiers: modifiers, mailHasFocus: focus)
        }
        // The sidebar with a folder selected, the window after a g key, the reading pane.
        #expect(plan("AXOutline") == .focusList)
        #expect(plan("AXWindow") == .focusList)
        #expect(plan("AXWebArea") == .focusList)
        // All selected but focus in the sidebar: back to the list first; a second Esc clears.
        #expect(plan("AXOutline", selected: 0) == .focusList)
        #expect(plan("AXTable", inList: true, selected: 40) == .clearSelection)
        #expect(plan("AXRow", inList: true, selected: 2) == .clearSelection)
        #expect(plan("AXTable", inList: true, selected: 1) == .pass)
        #expect(plan("AXTable", inList: true, selected: 0) == .pass)
        // Mail keeps Esc for what it cancels.
        #expect(plan("AXTextField") == .pass)               // renaming a mailbox
        #expect(plan("AXSearchField") == .pass)
        #expect(plan("AXTextArea") == .pass)
        #expect(plan("AXGroup", editable: true) == .pass)
        #expect(plan(sheet: true) == .pass)
        #expect(plan(menu: true) == .pass)
        #expect(plan("AXTable", inList: true, selected: 5, menu: true) == .pass)
        #expect(plan(modifiers: .shift) == .pass)
        #expect(plan(modifiers: .other) == .pass)
        #expect(plan(focus: false) == .pass)
        #expect(plan(nil) == .pass)
        // Outside the viewer (a window of its own is closed before this is asked).
        #expect(plan("AXWebArea", inViewer: false) == .pass)
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
        let label: String?
        let children: [DialogNode]
        let date: Date? = nil
        init(_ role: String, id: String? = nil, label: String? = nil, _ children: [DialogNode] = []) {
            self.role = role
            identifier = id
            self.label = label
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
    /// `u` with a folder selected: focus in the sidebar (an outline, like the list) or on the
    /// window itself is not in the message list, so u gives the list the keyboard; focus on
    /// a row or cell inside the list is.
    @Test func focusInTheSidebarIsNotTheList() {
        final class N { let parent: N?; init(_ parent: N?) { self.parent = parent } }
        let window = N(nil), split = N(window)
        let sidebar = N(split), folderRow = N(sidebar)
        let list = N(split), row = N(list), cell = N(row)
        func inside(_ focused: N?) -> Bool { MailKeys.isInside(focused, list, parent: { $0.parent }, same: { $0 === $1 }) }
        #expect(inside(list))
        #expect(inside(cell))
        #expect(!inside(sidebar))
        #expect(!inside(folderRow))
        #expect(!inside(window))
        #expect(!inside(nil))
        #expect(!MailKeys.isInside(cell, nil, parent: { $0.parent }, same: { $0 === $1 }))
        let viewer = MailKeys.WindowFacts(isStandardWindow: true, isViewer: true, hasSheetOrPopover: false, hasComposeControls: false, textFieldCount: 0)
        #expect(MailKeys.backToList(viewer, focusInList: inside(folderRow), sendEnabled: false) == .focusList)
    }

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

    /// u is undo (David, 2026-11-20 evening: "shouldn't u be undo?"), like z; g g and G are in
    /// the table and the list; g g and G only act from the list.
    @Test func uAndFirstAndLast() {
        #expect(MailKeys.outcome(for: "u", pending: nil) == .act(.menu("Edit", "Undo")))
        #expect(MailKeys.outcome(for: "z", pending: nil) == .act(.menu("Edit", "Undo")))
        #expect(MailKeys.outcome(for: "g", pending: "g") == .act(.firstMessage))
        #expect(MailKeys.outcome(for: "G", pending: nil) == .act(.lastMessage))
        #expect(MailKeys.outcome(for: "g", pending: nil) == .prefix("g"))
        #expect(!MailKeys.actsOnOneMessage(.firstMessage))
        #expect(!MailKeys.actsOnOneMessage(.lastMessage))
        #expect(MailKeys.help.contains { $0.0 == "u  or  z" && $0.1 == "undo" })
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
                       .menu("Message", "Mute"), .menu("Message", "Move to Junk"), .menu("Message", "Unread"), .showKeys] {
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

    /// From David's Check Mail at 19:11:29Z: a message open on its own has the viewer's id
    /// prefix ("…window.39") but no "Main Window" split group; it must not count as the
    /// viewer, or Esc, u and its keys do nothing there.
    @MainActor @Test func aMessageWindowIsNotTheViewer() {
        let messageWindow = Node("AXWindow", id: "Mail.messageViewer.window.39", [
            Node("AXGroup"),
            Node("AXScrollArea", id: "_MAIL_MESSAGE_CONTENT", [Node("AXGroup", id: "message_view")]),
            Node("AXToolbar", [Node("AXGroup", [Node("AXButton"), Node("AXButton")])]),
            Node("AXButton"),
        ])
        let viewer = Node("AXWindow", id: "Mail.messageViewer.window.1", [
            Node("AXSplitGroup", id: "Main Window", [Node("AXSplitGroup", id: "Main Window Preview Pane Vertical")]),
            Node("AXToolbar"),
        ])
        #expect(!MailKeys.isMainViewer(messageWindow))
        #expect(MailKeys.isMainViewer(viewer))
        #expect(!MailKeys.isMainViewer(Node("AXWindow", id: "_NS:41", [Node("AXSplitGroup", id: "Main Window")])))
    }

    /// Mail has no Send item outside a message being written: missing is off; unreadable
    /// menus count as on, so keys fail open.
    @Test func aMissingSendIsOff() {
        #expect(!MailKeys.sendIsOn(menuRead: true, send: nil))
        #expect(!MailKeys.sendIsOn(menuRead: true, send: false))
        #expect(MailKeys.sendIsOn(menuRead: true, send: true))
        #expect(MailKeys.sendIsOn(menuRead: false, send: nil))
    }

    @MainActor final class FakeWindow: MailKeys.ClosableWindow {
        let isMainViewer: Bool
        let hasButton: Bool
        let answer: Bool
        var presses = 0
        init(viewer: Bool = false, hasButton: Bool = true, answer: Bool) {
            isMainViewer = viewer
            self.hasButton = hasButton
            self.answer = answer
        }
        func pressCloseButton() -> Bool? {
            guard hasButton else { return nil }
            presses += 1
            return answer
        }
    }

    /// One press of the captured window's own close button, nothing else (2026-11-20: after
    /// an error from that press, File › Close closed Mail's main viewer). An error answer is
    /// not a reason to try anything else, and the viewer is never closed.
    @MainActor @Test func closingIsOnePressAndNeverTheViewer() {
        let erring = FakeWindow(answer: false)
        #expect(MailKeys.closeOnce(erring) == .pressAnswered)
        #expect(erring.presses == 1)
        let fine = FakeWindow(answer: true)
        #expect(MailKeys.closeOnce(fine) == .pressed)
        #expect(fine.presses == 1)
        let buttonless = FakeWindow(hasButton: false, answer: true)
        #expect(MailKeys.closeOnce(buttonless) == .noCloseButton)
        let viewer = FakeWindow(viewer: true, answer: true)
        #expect(MailKeys.closeOnce(viewer) == .refusedMainViewer)
        #expect(viewer.presses == 0)
    }

    /// The close path has no way to a menu item: MailKeyActions.close calls closeOnce and
    /// logs, and closeOnce takes nothing that could press "Close" or any front-window action.
    @Test func theClosePathNeverPressesAMenuItem() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenShelf/Mail/MailKeyTap.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "    static func close(_ window: AXUIElement) {"))
        let end = try #require(source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex))
        let body = source[start.lowerBound..<end.upperBound]
        #expect(!body.contains("press("))
        #expect(!body.contains("pressAnywhere("))
        #expect(!body.contains("\"Close\""))
    }

    /// After closing the message window, Archive or Delete is pressed in the viewer only when
    /// the window is gone, the viewer is in front and its selection is still the bound one.
    @Test func theViewerIsPressedOnlyWhenAllThreeHold() {
        let ids: Set<String> = ["a@x", "b@x"]
        #expect(MailKeys.mayPressInViewer(messageWindowGone: true, frontIsMainViewer: true, bound: ids, current: ids))
        #expect(!MailKeys.mayPressInViewer(messageWindowGone: false, frontIsMainViewer: true, bound: ids, current: ids))
        #expect(!MailKeys.mayPressInViewer(messageWindowGone: true, frontIsMainViewer: false, bound: ids, current: ids))
        #expect(!MailKeys.mayPressInViewer(messageWindowGone: true, frontIsMainViewer: true, bound: ids, current: ["a@x"]))
        #expect(!MailKeys.mayPressInViewer(messageWindowGone: true, frontIsMainViewer: true, bound: nil, current: ids))
        #expect(!MailKeys.mayPressInViewer(messageWindowGone: true, frontIsMainViewer: true, bound: [], current: []))
    }

    /// A message window's toolbar as David's Check Mail showed it: the Archive, Delete and
    /// Junk segments inside a group, named by description. Found one level down.
    @MainActor @Test func findsTheSegmentedArchiveAndDelete() {
        let archive = Node("AXButton", label: "Archive"), delete = Node("AXButton", label: "Delete")
        let window = Node("AXWindow", id: "Mail.messageViewer.window.39", [
            Node("AXGroup"), Node("AXScrollArea"),
            Node("AXToolbar", [
                Node("AXGroup", [archive, delete, Node("AXButton", label: "Junk")]),
                Node("AXGroup", [Node("AXButton", label: "Reply"), Node("AXButton", label: "Reply All"), Node("AXButton", label: "Forward")]),
                Node("AXButton", label: "Print"),
            ]),
            Node("AXButton"),
        ])
        #expect(MailKeys.toolbarButton("Archive", in: window) as? Node === archive)
        #expect(MailKeys.toolbarButton("Delete", in: window) as? Node === delete)
        #expect(MailKeys.toolbarButton("Archive", in: Node("AXWindow", [Node("AXGroup", [Node("AXButton", label: "Archive")])])) == nil)
    }

    /// After pressing the open message's own button, only a closed window counts as done; an
    /// error answer with the window still open is "unsure", never "no button".
    @Test func theOpenMessageResultComesFromTheWindow() {
        #expect(MailKeys.openMessageResult(buttonFound: true, windowGone: true) == .done)
        #expect(MailKeys.openMessageResult(buttonFound: true, windowGone: false) == .unsure)
        #expect(MailKeys.openMessageResult(buttonFound: false, windowGone: false) == .noButton)
    }

    /// Toolbar button first, then list focus and the menu; a proven change ends it; an
    /// ambiguous one stops without a second route; no change moves to the next route.
    @Test func actionRoutesInOrderAndNeverTwiceAfterAChange() {
        // The list with the menu first, then the toolbar button.
        #expect(MailKeys.nextActionStep(tried: [], last: nil, toolbarAvailable: true) == .attempt(.listThenMenu))
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu], last: .changed, toolbarAvailable: true) == .done(.listThenMenu))
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu], last: .unchanged, toolbarAvailable: true) == .attempt(.toolbar))
        // 2026-11-20: a false success skipped the next route; an ambiguous result now stops, unsure.
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu], last: .ambiguous, toolbarAvailable: true) == .unsure(.listThenMenu))
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu, .toolbar], last: .changed, toolbarAvailable: true) == .done(.toolbar))
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu, .toolbar], last: .unchanged, toolbarAvailable: true) == .gaveUp)
        #expect(MailKeys.nextActionStep(tried: [], last: nil, toolbarAvailable: false) == .attempt(.listThenMenu))
        #expect(MailKeys.nextActionStep(tried: [.listThenMenu], last: .unchanged, toolbarAvailable: false) == .gaveUp)
    }

    /// What proves a command, from David's log shape (14 rows, 9 selected).
    @Test func whatProvesACommand() {
        typealias S = MailKeys.ListSnapshot
        let nine = Set((1...9).map { "m\($0)@x" })
        let before = S(rows: 14, selected: nine)
        // His case: the selection narrowed to one of the nine, same rows: not an archive.
        #expect(MailKeys.outcome(before, S(rows: 14, selected: ["m3@x"]), .rowsLeave) == .ambiguous)
        // The selection moved to another message, same rows: not an archive either.
        #expect(MailKeys.outcome(before, S(rows: 14, selected: ["other@x"]), .rowsLeave) == .ambiguous)
        // Rows gone but some of the messages still selected: not proven.
        #expect(MailKeys.outcome(before, S(rows: 13, selected: ["m1@x"]), .rowsLeave) == .ambiguous)
        // Rows gone and none of them selected: proven.
        #expect(MailKeys.outcome(before, S(rows: 13, selected: ["next@x"]), .rowsLeave) == .changed)
        #expect(MailKeys.outcome(before, S(rows: 13, selected: []), .rowsLeave) == .changed)
        // Exactly as before.
        #expect(MailKeys.outcome(before, before, .rowsLeave) == .unchanged)
        // Flag and read: the same messages, their state changed.
        let one = S(rows: 14, selected: ["a@x"], flagged: ["a@x": false], read: ["a@x": false])
        #expect(MailKeys.outcome(one, S(rows: 14, selected: ["a@x"], flagged: ["a@x": true], read: ["a@x": false]), .flag) == .changed)
        #expect(MailKeys.outcome(one, S(rows: 14, selected: ["a@x"], flagged: ["a@x": false], read: ["a@x": true]), .read) == .changed)
        #expect(MailKeys.outcome(one, S(rows: 14, selected: ["b@x"], flagged: ["b@x": true], read: ["b@x": false]), .flag) == .ambiguous)
        #expect(MailKeys.outcome(one, one, .flag) == .unchanged)
        // Nothing selected before: never proven.
        #expect(MailKeys.outcome(S(rows: 14, selected: []), S(rows: 13, selected: []), .rowsLeave) == .ambiguous)
        #expect(MailKeys.outcome(one, one, .none) == .changed)
        #expect(MailKeys.verification(for: "Archive") == .rowsLeave)
        #expect(MailKeys.toolbarLabel(for: "Move to Junk") == "Junk")
    }

    /// David's go-to keys (2026-11-20): g i All Inboxes, g f Flagged, g s All Sent, g t All
    /// Trash, g d All Drafts, g a All Mail (David, 2026-11-20 evening: "there is no All Archive"); g g
    /// stays the first message.
    @Test func goToKeys() {
        let expected: [Character: MailKeys.Action] = ["i": .favorite("Inbox"), "f": .favorite("Flagged"), "s": .favorite("Sent"),
                                                      "t": .favorite("Trash"), "d": .favorite("Drafts"), "a": .favorite("All Mail"), "A": .favorite("Archive"), "T": .favorite("Today"), "g": .firstMessage,
                                                      "j": .favorite("Junk"), "u": .favorite("Follow Up"), "l": .favorite("Send Later"), "r": .favorite("Remind Me")]
        for (key, action) in expected { #expect(MailKeys.outcome(for: key, pending: "g") == .act(action), "g \(key)") }
        #expect(MailKeys.outcome(for: "g", pending: nil) == .prefix("g"))
        #expect(MailKeys.help.contains { $0.0.contains("g a") && $0.1.contains("All Mail") && !$0.1.contains("All Archive") })
        #expect(MailKeys.help.contains { $0.0.contains("g A") && $0.1.hasPrefix("Archive") })
        // g A's mailbox is the row titled Archive, as Mail shows it (no "All Archive").
        #expect(MailKeys.unifiedIndex(for: "Archive", in: ["All Mail", "Archive (2)"]) == 1)
        #expect(MailKeys.unifiedTitles(for: "Archive") == ["Archive"])
        // g T: Today, found by its title like the others; g t stays All Trash.
        #expect(MailKeys.help.contains { $0.0.contains("g T") && $0.1.contains("Today") })
        #expect(MailKeys.unifiedIndex(for: "Today", in: ["All Inboxes", "Today (4)"]) == 1)
        #expect(MailKeys.outcome(for: "t", pending: "g") == .act(.favorite("Trash")))
    }

    /// g a's script answer: which All Mail it showed, none, or a failure; and the viewer's
    /// title "All Mail" (with or without an account after it) counts as arrived.
    @Test func allMailAnswers() {
        #expect(MailKeys.allMailResult("#OK selected\n") == .selected)
        #expect(MailKeys.allMailResult("#OK first") == .first)
        #expect(MailKeys.allMailResult("#NONE") == .none)
        #expect(MailKeys.allMailResult(nil) == .failed)
        #expect(MailKeys.allMailResult("") == .failed)
        #expect(MailKeys.unifiedIndex(for: "All Mail", in: ["All Inboxes", "All Mail (3)"]) == 1)
        #expect(MailKeys.showsUnified("All Mail", windowTitle: "All Mail – 12 messages"))
        #expect(!MailKeys.showsUnified("All Mail", windowTitle: "All Inboxes"))
        // It asks for the mailbox by name and never searches or reads messages.
        let script = MailScripts.showAllMail
        #expect(script.contains("exists mailbox \"All Mail\""))
        #expect(!script.contains("messages of"))
        #expect(script.contains("with timeout of 5 seconds"))
    }

    /// The unified mailbox is found by Mail's titles now: "All …" with several accounts, the
    /// plain name with one, a count after it ignored; one account's own mailbox never counts.
    @Test func unifiedMailboxesByTitle() {
        #expect(MailKeys.unifiedIndex(for: "Inbox", in: ["VIPs", "All Inboxes", "Inbox"]) == 1)
        #expect(MailKeys.unifiedIndex(for: "Inbox", in: ["Inbox"]) == 0)
        #expect(MailKeys.unifiedIndex(for: "Inbox", in: ["All Inboxes (12)"]) == 0)
        #expect(MailKeys.unifiedIndex(for: "Sent", in: ["Sent — Gmail", "All Sent"]) == 1)
        #expect(MailKeys.unifiedIndex(for: "Trash", in: ["Drafts", "All Trash"]) == 1)
        #expect(MailKeys.unifiedIndex(for: "Flagged", in: ["Flagged"]) == 0)
        #expect(MailKeys.unifiedIndex(for: "Drafts", in: ["VIPs", "Notes"]) == nil)
        #expect(MailKeys.showsUnified("Inbox", windowTitle: "All Inboxes – 1,204 messages"))
        #expect(MailKeys.showsUnified("Inbox", windowTitle: "Inbox"))
        #expect(!MailKeys.showsUnified("Inbox", windowTitle: "Sent – 12 messages"))
        #expect(!MailKeys.showsUnified("Sent", windowTitle: nil))
    }

    /// g then j, u, l or r inside the prefix time go to the mailbox and never run the plain
    /// key (next message, back to the list, move picker, reply); on their own those keys
    /// keep their meaning.
    @Test func gPrefixedKeysNeverRunThePlainKey() {
        for (key, mailbox) in [("j", "Junk"), ("u", "Follow Up"), ("l", "Send Later"), ("r", "Remind Me")] as [(Character, String)] {
            #expect(MailKeys.outcome(for: key, pending: "g") == .act(.favorite(mailbox)), "g \(key)")
        }
        #expect(MailKeys.outcome(for: "j", pending: nil) == .act(.nextMessage))
        #expect(MailKeys.outcome(for: "u", pending: nil) == .act(.menu("Edit", "Undo")))
        #expect(MailKeys.outcome(for: "l", pending: nil) == .act(.file))
        #expect(MailKeys.outcome(for: "r", pending: nil) == .act(.menu("Message", "Reply")))
        #expect(MailKeys.unifiedIndex(for: "Junk", in: ["All Junk"]) == 0)
        #expect(MailKeys.unifiedIndex(for: "Remind Me", in: ["VIPs", "Remind Me"]) == 1)
        #expect(MailKeys.unifiedIndex(for: "Send Later", in: ["Send Later (2)"]) == 0)
        #expect(MailKeys.help.contains { $0.0.contains("g r") && $0.1.contains("Remind Me") })
    }
}
