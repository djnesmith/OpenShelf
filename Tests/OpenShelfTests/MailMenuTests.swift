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

    static func window(pickers: Int = 1, settable: Bool = true, keep: @escaping (Date) -> Date = { $0 }) -> (FakeNode, [FakeNode], FakeNode, FakeNode) {
        let pickerNodes = (0..<pickers).map { _ in FakeNode("AXDateTimeArea", date: .distantPast, settable: settable, keep: keep) }
        let remind = FakeNode("AXButton", "Remind Me")
        let cancel = FakeNode("AXButton", "Cancel")
        let group = FakeNode("AXGroup", nil, pickerNodes + [FakeNode("AXButton", "Schedule")])
        return (FakeNode("AXSheet", nil, [group, cancel, remind]), pickerNodes, remind, cancel)
    }

    @Test func setsTheDateThenPressesRemindMe() {
        let (window, pickers, remind, cancel) = Self.window()
        #expect(RemindDialog.fill(window, with: Self.when) == .reminded)
        #expect(pickers[0].date == Self.when)
        #expect(remind.pressed == 1)
        #expect(cancel.pressed == 0)
    }

    /// No picker, two pickers, a picker that won't take the date or keeps a different
    /// time: the window is cancelled, never "Remind Me".
    @Test func anythingUnexpectedCancels() {
        let cases: [(FakeNode, FakeNode, FakeNode)] = [
            { let w = Self.window(pickers: 0); return (w.0, w.2, w.3) }(),
            { let w = Self.window(pickers: 2); return (w.0, w.2, w.3) }(),
            { let w = Self.window(settable: false); return (w.0, w.2, w.3) }(),
            { let w = Self.window(keep: { $0.addingTimeInterval(3600) }); return (w.0, w.2, w.3) }(),
        ]
        for (window, remind, cancel) in cases {
            guard case .cancelled = RemindDialog.fill(window, with: Self.when) else {
                Issue.record("not cancelled")
                continue
            }
            #expect(remind.pressed == 0)
            #expect(cancel.pressed == 1)
        }
        // Seconds dropped is fine: Mail keeps minutes.
        let (window, _, remind, _) = Self.window(keep: { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded(.down) * 60) })
        #expect(RemindDialog.fill(window, with: Self.when.addingTimeInterval(20)) == .reminded)
        #expect(remind.pressed == 1)
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
