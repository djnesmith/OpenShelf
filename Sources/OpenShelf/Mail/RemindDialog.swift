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

/// Fills in Mail's "Remind Me Later…" dialog. On David's Mac (screenshot, 2026-11-20) it
/// is a sheet with "Set a time for when Mail should remind you about this message.", a
/// date picker and a separate time picker, and the buttons Cancel and Schedule. Every
/// picker gets the whole date and must read it back to the minute before Schedule is
/// pressed; anything else presses Cancel, so a reminder is never set to a wrong time and
/// the dialog is never left open.
@MainActor
enum RemindDialog {
    /// "Schedule" on David's Mail; "Remind Me" kept for the title Mail 16's strings had.
    static let confirmTitles: Set<String> = ["Schedule", "Remind Me"]
    static let cancelTitle = "Cancel"
    static let datePickerRoles: Set<String> = ["AXDateTimeArea", "AXDateField"]
    /// The date and the time pickers, each perhaps with a calendar or clock beside it.
    static let maxPickers = 4

    enum Outcome: Equatable {
        case reminded
        /// The dialog was cancelled, and why.
        case cancelled(String)
    }

    /// Whether `node` is the dialog: a confirm button, a Cancel button and a date picker.
    static func isDialog(_ node: DialogNode) -> Bool {
        !buttons(confirmTitles, in: node).isEmpty && !buttons([cancelTitle], in: node).isEmpty
            && !all(in: node, where: { datePickerRoles.contains($0.role) }).isEmpty
    }

    /// Sets `date` on every picker and presses Schedule, or cancels with the reason.
    static func fill(_ window: DialogNode, with date: Date, calendar: Calendar = .current) -> Outcome {
        let pickers = all(in: window) { datePickerRoles.contains($0.role) }
        let confirm = buttons(confirmTitles, in: window)
        let cancel = buttons([cancelTitle], in: window)
        func giveUp(_ reason: String) -> Outcome {
            _ = cancel.first?.press()
            return .cancelled(reason)
        }
        guard (1...maxPickers).contains(pickers.count) else { return giveUp("expected a date and a time picker, found \(pickers.count) pickers") }
        guard confirm.count == 1, let button = confirm.first else { return giveUp("no single “Schedule” button") }
        for (index, picker) in pickers.enumerated() where !picker.setDate(date) {
            return giveUp("picker \(index + 1) of \(pickers.count) couldn't be set")
        }
        // Mail keeps minutes: every picker must read back the time asked for, to the minute.
        for (index, picker) in pickers.enumerated() {
            guard let set = picker.date, calendar.isDate(set, equalTo: date, toGranularity: .minute) else {
                let shown = picker.date.map { SnoozeTime.describe($0, calendar: calendar) } ?? "nothing"
                return giveUp("picker \(index + 1) of \(pickers.count) read back \(shown)")
            }
        }
        guard button.press() else { return giveUp("“Schedule” couldn't be pressed") }
        return .reminded
    }

    /// Presses the dialog's Cancel.
    static func cancel(_ dialog: DialogNode) -> Bool {
        buttons([cancelTitle], in: dialog).first?.press() ?? false
    }

    private static func buttons(_ titles: Set<String>, in node: DialogNode) -> [DialogNode] {
        all(in: node) { $0.role == kAXButtonRole && $0.title.map(titles.contains) == true }
    }

    static func all(in node: DialogNode, where match: (DialogNode) -> Bool) -> [DialogNode] {
        node.children.flatMap { child in (match(child) ? [child] : []) + all(in: child, where: match) }
    }

    /// The dialog among `windows` (each window, then its sheets), or nil.
    static func find(in windows: [DialogNode]) -> DialogNode? {
        for window in windows {
            let sheets = window.children.filter { $0.role == kAXSheetRole }
            if let match = (sheets + [window]).first(where: isDialog) { return match }
        }
        return nil
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
