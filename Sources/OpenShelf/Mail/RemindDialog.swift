import AppKit
import ApplicationServices

/// An element of Mail's "Remind Me Later…" window. A protocol, so tests use a fake.
@MainActor
protocol DialogNode {
    var role: String { get }
    var title: String? { get }
    var children: [DialogNode] { get }
    /// A date picker's date; nil for anything else.
    var date: Date? { get }
    /// Sets a date picker's date; false when it can't be set.
    func setDate(_ date: Date) -> Bool
    func press() -> Bool
}

/// Fills in Mail's "Remind Me Later…" window (title strings from Mail 16's
/// `DatePickerViewController.loctable`): one date picker, then "Remind Me". Anything
/// unexpected cancels the window instead, so a reminder is never set to a wrong time.
@MainActor
enum RemindDialog {
    static let remindTitle = "Remind Me"
    static let cancelTitle = "Cancel"
    static let datePickerRoles: Set<String> = ["AXDateTimeArea", "AXDateField"]

    enum Outcome: Equatable {
        case reminded
        /// The window was cancelled, and why.
        case cancelled(String)
    }

    /// Sets `date` and presses Remind Me, or cancels with the reason.
    static func fill(_ window: DialogNode, with date: Date, calendar: Calendar = .current) -> Outcome {
        let pickers = all(in: window) { datePickerRoles.contains($0.role) }
        let remind = all(in: window) { $0.role == kAXButtonRole && $0.title == remindTitle }
        let cancel = all(in: window) { $0.role == kAXButtonRole && $0.title == cancelTitle }
        func giveUp(_ reason: String) -> Outcome {
            _ = cancel.first?.press()
            return .cancelled(reason)
        }
        guard pickers.count == 1, let picker = pickers.first else { return giveUp("expected one date picker, found \(pickers.count)") }
        guard remind.count == 1, let button = remind.first else { return giveUp("no single “Remind Me” button") }
        guard picker.setDate(date) else { return giveUp("the date couldn't be set") }
        // Mail keeps minutes: the time read back must be the one asked for, to the minute.
        guard let set = picker.date, calendar.isDate(set, equalTo: date, toGranularity: .minute) else {
            return giveUp("the date read back differently")
        }
        guard button.press() else { return giveUp("“Remind Me” couldn't be pressed") }
        return .reminded
    }

    private static func all(in node: DialogNode, where match: (DialogNode) -> Bool) -> [DialogNode] {
        node.children.flatMap { child in (match(child) ? [child] : []) + all(in: child, where: match) }
    }
}

/// An element of another app's window, read and set through Accessibility.
@MainActor
struct AXDialogNode: DialogNode {
    let element: AXUIElement

    var role: String { AXMenuNode.string(element, kAXRoleAttribute) ?? "" }
    var title: String? { AXMenuNode.string(element, kAXTitleAttribute) }
    var children: [DialogNode] { AXMenuNode.childElements(element).map(AXDialogNode.init) }

    var date: Date? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? Date
    }

    func setDate(_ date: Date) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, date as CFDate) == .success
    }

    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
