import AppKit
import Testing
@testable import OpenShelf

/// Mail's menu and Remind Me window, against fakes: nothing here touches Mail.
@MainActor
struct MailMenuTests {
    final class FakeItem: MenuNode {
        let title: String
        let isEnabled: Bool
        let children: [MenuNode]
        var pressed = 0
        init(_ title: String, enabled: Bool = true, _ children: [MenuNode] = []) {
            self.title = title
            self.isEnabled = enabled
            self.children = children
        }
        func press() -> Bool { pressed += 1; return true }
    }

    static func mailBar(remindTitle: String = "Remind Me Later…") -> [MenuNode] {
        [
            FakeItem("Mail"),
            FakeItem("Message", [
                FakeItem("Send", enabled: false),
                FakeItem("Archive"),
                FakeItem("Remind Me", [FakeItem("Remind Me in 1 Hour"), FakeItem(remindTitle)]),
            ]),
        ]
    }

    @Test func findsItemsByTheirExactTitles() {
        let bar = Self.mailBar()
        #expect(MailMenu.find(MailMenu.remindMeLater, in: bar)?.title == "Remind Me Later…")
        #expect(MailMenu.find(MailMenu.send, in: bar)?.isEnabled == false)
        #expect(MailMenu.find(["Message", "Remind"], in: bar) == nil)
        #expect(MailMenu.missing(MailMenu.snoozePaths, in: bar).isEmpty)
    }

    /// Apple renaming an item (three dots instead of "…") is reported, never guessed at.
    @Test func aRenamedItemIsReportedMissing() {
        let bar = Self.mailBar(remindTitle: "Remind Me Later...")
        #expect(MailMenu.missing(MailMenu.snoozePaths, in: bar) == ["Message › Remind Me › Remind Me Later…"])
    }

    final class FakeNode: DialogNode {
        let role: String
        let title: String?
        let children: [DialogNode]
        var date: Date?
        let settable: Bool
        /// What the control keeps when set (a picker that drops minutes, say).
        let keep: (Date) -> Date
        var pressed = 0
        init(_ role: String, _ title: String? = nil, date: Date? = nil, settable: Bool = true, keep: @escaping (Date) -> Date = { $0 }, _ children: [DialogNode] = []) {
            self.role = role
            self.title = title
            self.date = date
            self.settable = settable
            self.keep = keep
            self.children = children
        }
        func setDate(_ new: Date) -> Bool {
            guard settable else { return false }
            date = keep(new)
            return true
        }
        func press() -> Bool { pressed += 1; return true }
    }

    static let when = Date(timeIntervalSince1970: 1_800_000_000)

    /// Mail's dialog as on David's Mac (2026-11-20): a sheet with a line of text, a date
    /// picker and a time picker (each with a calendar or clock), Cancel and Schedule.
    struct Dialog {
        let sheet: FakeNode
        let pickers: [FakeNode]
        let schedule: FakeNode
        let cancel: FakeNode
    }

    static func dialog(pickers: Int = 4, settable: Bool = true, keep: @escaping (Int, Date) -> Date = { $1 },
                       confirm: [String] = ["Schedule"], hasCancel: Bool = true) -> Dialog {
        let pickerNodes = (0..<pickers).map { index in
            FakeNode("AXDateTimeArea", date: .distantPast, settable: settable, keep: { keep(index, $0) })
        }
        let confirms = confirm.map { FakeNode("AXButton", $0) }
        let cancel = FakeNode("AXButton", "Cancel")
        let group = FakeNode("AXGroup", nil, pickerNodes)
        let sheet = FakeNode("AXSheet", nil, [FakeNode("AXStaticText"), group] + (hasCancel ? [cancel] : []) + confirms)
        return Dialog(sheet: sheet, pickers: pickerNodes, schedule: confirms.first ?? FakeNode("AXButton", "none"), cancel: cancel)
    }

    @Test func setsEveryPickerThenPressesSchedule() {
        for count in [1, 2, 4] {
            let dialog = Self.dialog(pickers: count)
            #expect(RemindDialog.fill(dialog.sheet, with: Self.when) == .reminded)
            #expect(dialog.pickers.allSatisfy { $0.date == Self.when })
            #expect(dialog.schedule.pressed == 1)
            #expect(dialog.cancel.pressed == 0)
        }
    }

    /// Mail 16's older title still works.
    @Test func anOlderRemindMeTitleStillWorks() {
        let dialog = Self.dialog(confirm: ["Remind Me"])
        #expect(RemindDialog.fill(dialog.sheet, with: Self.when) == .reminded)
        #expect(dialog.schedule.pressed == 1)
    }

    /// No picker, too many, one that won't take the date, a time picker that keeps another
    /// time, a date picker that drops to midnight, no or two Schedule buttons: Cancel is
    /// pressed, never Schedule.
    @Test func anythingUnexpectedCancels() {
        let midnight: (Int, Date) -> Date = { index, date in index == 0 ? Calendar.current.startOfDay(for: date) : date }
        let cases: [Dialog] = [
            Self.dialog(pickers: 0),
            Self.dialog(pickers: 5),
            Self.dialog(settable: false),
            Self.dialog(keep: { index, date in index == 1 ? date.addingTimeInterval(3600) : date }),
            Self.dialog(keep: midnight),
            Self.dialog(confirm: []),
            Self.dialog(confirm: ["Schedule", "Schedule"]),
        ]
        for dialog in cases {
            guard case .cancelled = RemindDialog.fill(dialog.sheet, with: Self.when) else {
                Issue.record("not cancelled")
                continue
            }
            #expect(dialog.schedule.pressed == 0)
            #expect(dialog.cancel.pressed == 1)
        }
        // Seconds dropped is fine: Mail keeps minutes.
        let dialog = Self.dialog(keep: { _, date in Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60) })
        #expect(RemindDialog.fill(dialog.sheet, with: Self.when.addingTimeInterval(20)) == .reminded)
        #expect(dialog.schedule.pressed == 1)
    }

    /// The dialog is found as a sheet on any of Mail's windows, not only the front one,
    /// and only when it has Cancel, Schedule and a picker.
    @Test func findsTheDialogAsASheetOnAnyWindow() {
        let dialog = Self.dialog()
        let viewer = FakeNode("AXWindow", nil, [FakeNode("AXSplitGroup"), dialog.sheet])
        let other = FakeNode("AXWindow", nil, [FakeNode("AXButton", "Cancel")])
        #expect((RemindDialog.find(in: [other, viewer]) as? FakeNode) === dialog.sheet)
        #expect(RemindDialog.find(in: [other]) == nil)
        #expect(RemindDialog.find(in: [FakeNode("AXWindow", nil, [Self.dialog(hasCancel: false).sheet])]) == nil)
        #expect(RemindDialog.find(in: [FakeNode("AXWindow", nil, [Self.dialog(pickers: 0).sheet])]) == nil)
        // A dialog shown as a window of its own.
        let own = FakeNode("AXWindow", nil, Self.dialog().sheet.children)
        #expect((RemindDialog.find(in: [own]) as? FakeNode) === own)
        #expect(RemindDialog.cancel(dialog.sheet))
        #expect(dialog.cancel.pressed == 1)
    }

    /// The prompt takes the keyboard without activating OpenShelf, with the cursor in
    /// the field (David, 2026-11-20: the field had no cursor after `b`).
    @Test func thePromptOpensWithTheCursorInTheField() {
        let prompt = SnoozePrompt()
        let panel = prompt.prepare { _ in }
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(panel.initialFirstResponder === prompt.promptField)
    }

    /// The shortcut is live only while Mail is in front.
    @Test func listensOnlyWhileMailIsInFront() {
        #expect(MailHelpers.shouldListen(front: "com.apple.mail"))
        #expect(!MailHelpers.shouldListen(front: "com.apple.Safari"))
        #expect(!MailHelpers.shouldListen(front: nil))
        #expect(MailHelpers.defaultPromptShortcut.displayString == "⌃⌥S")
        #expect(!MailHelpers(defaults: UserDefaults(suiteName: "OpenShelfTests.mail.\(UUID())")!).archivesAfterRemind)
    }

    /// Before the prompt opens: menus readable, items there, a message selected.
    @Test func checksMailBeforeSnoozing() {
        #expect(MailHelpers.problem(with: nil) == "OpenShelf can't read Mail's menus (Accessibility)")
        #expect(MailHelpers.problem(with: Self.mailBar()) == nil)
        #expect(MailHelpers.problem(with: Self.mailBar(remindTitle: "Remind Me Later..."))?.hasPrefix("Mail's menu has changed") == true)
        let noSelection: [MenuNode] = [FakeItem("Message", [FakeItem("Archive"), FakeItem("Remind Me", [FakeItem("Remind Me Later…", enabled: false)])])]
        #expect(MailHelpers.problem(with: noSelection) == "Select a message in Mail's list first")
    }

    /// The prompt shows what it understood; Return chooses it; ⌘-digit picks a preset;
    /// Esc closes without choosing. The prompt is never put on screen here.
    @Test func thePromptChoosesATime() {
        let prompt = SnoozePrompt()
        prompt.calendar = SnoozeTimeTests.calendar
        prompt.now = { SnoozeTimeTests.wednesday(10) }
        var chosen: [Date] = []
        prompt.prepare { chosen.append($0) }
        #expect(prompt.understoodText == "Type a time, or pick one below")
        prompt.promptField.stringValue = "fri 2pm"
        prompt.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(prompt.understoodText == "→ Fri, Nov 20 at 2:00 PM")
        let editor = NSTextView()
        #expect(prompt.control(prompt.promptField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(chosen.map { SnoozeTime.describe($0, calendar: SnoozeTimeTests.calendar) } == ["Fri, Nov 20 at 2:00 PM"])

        prompt.prepare { chosen.append($0) }
        prompt.promptField.stringValue = "banana"
        prompt.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(prompt.understoodText == "Not understood")
        _ = prompt.control(prompt.promptField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen.count == 1)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "5", charactersIgnoringModifiers: "5", isARepeat: false, keyCode: 23)!
        #expect(prompt.promptPanel?.performKeyEquivalent(with: key) == true)
        #expect(chosen.map { SnoozeTime.describe($0, calendar: SnoozeTimeTests.calendar) }.last == "Sat, Nov 21 at 7:00 AM")

        prompt.prepare { chosen.append($0) }
        prompt.promptField.stringValue = "tonight"
        _ = prompt.control(prompt.promptField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        _ = prompt.control(prompt.promptField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen.count == 2)
    }
}
