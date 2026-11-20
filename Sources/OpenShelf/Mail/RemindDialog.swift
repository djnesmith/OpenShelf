import AppKit
import ApplicationServices

/// An element of Mail's "Remind Me Later…" window. A protocol, so tests use a fake.
@MainActor
protocol DialogNode {
    var role: String { get }
    var title: String? { get }
    /// The Accessibility identifier, where there is one.
    var identifier: String? { get }
    var children: [DialogNode] { get }
    /// A date picker's date; nil for anything else.
    var date: Date? { get }
    /// Sets a date picker's date; false when it can't be set.
    func setDate(_ date: Date) -> Bool
    func press() -> Bool
    /// What the control holds, for the snooze log: "date 2026-11-20T13:25:00Z", "no value".
    var valueDescription: String { get }
    /// Presses, and says how it went for the snooze log ("ok", "AXError -25204").
    func pressReporting() -> (ok: Bool, detail: String)
}

extension DialogNode {
    var identifier: String? { nil }
    var valueDescription: String { date.map { "date " + ISO8601DateFormatter().string(from: $0) } ?? "no date" }
    func pressReporting() -> (ok: Bool, detail: String) {
        let ok = press()
        return (ok, ok ? "ok" : "failed")
    }
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
        /// Schedule was pressed. `pressOK` is what Accessibility answered, which can be an
        /// error although Mail took the press (2026-11-20: the sheet closes during it), so
        /// it is logged and never shown as a failure.
        case scheduled(pressOK: Bool)
        /// Cancel was pressed and Schedule never was, with a short reason.
        case cancelled(String)
    }

    /// Whether `node` is the dialog: a confirm button, a Cancel button and a date picker.
    static func isDialog(_ node: DialogNode) -> Bool {
        !buttons(confirmTitles, in: node).isEmpty && !buttons([cancelTitle], in: node).isEmpty
            && !all(in: node, where: { datePickerRoles.contains($0.role) }).isEmpty
    }

    /// Sets `date` on every picker and presses Schedule, or cancels with a short reason.
    /// Every step goes to `note`, for the snooze log. Nothing is cancelled once Schedule
    /// has been pressed.
    static func fill(_ window: DialogNode, with date: Date, calendar: Calendar = .current, note: (String) -> Void = { _ in }) -> Outcome {
        let pickers = all(in: window) { datePickerRoles.contains($0.role) }
        let confirm = buttons(confirmTitles, in: window)
        let cancel = buttons([cancelTitle], in: window)
        note("found \(pickers.count) pickers; buttons: \(all(in: window) { $0.role == kAXButtonRole }.map { $0.title ?? "?" }.joined(separator: ", "))")
        func giveUp(_ reason: String) -> Outcome {
            let pressed = cancel.first?.pressReporting().detail ?? "no Cancel button"
            note("cancelled: \(reason); Cancel press \(pressed)")
            return .cancelled(reason)
        }
        guard (1...maxPickers).contains(pickers.count) else { return giveUp("found \(pickers.count) time pickers") }
        guard confirm.count == 1, let button = confirm.first else { return giveUp("no single Schedule button") }
        for (index, picker) in pickers.enumerated() {
            note("picker \(index + 1): \(picker.role), before \(picker.valueDescription)")
            guard picker.setDate(date) else { return giveUp("picker \(index + 1) wouldn't take the time") }
        }
        // Read back: a picker may show only the day or only the time (Mail keeps minutes), so
        // each must match the day or the time, and together they must give both.
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: date)
        var dayShown = false, timeShown = false
        for (index, picker) in pickers.enumerated() {
            note("picker \(index + 1): after \(picker.valueDescription)")
            guard let set = picker.date else { return giveUp("picker \(index + 1) read back nothing") }
            let sameDay = calendar.dateComponents([.year, .month, .day], from: set) == day
            let sameTime = calendar.dateComponents([.hour, .minute], from: set) == time
            guard sameDay || sameTime else { return giveUp("picker \(index + 1) read back \(SnoozeTime.describe(set, calendar: calendar))") }
            dayShown = dayShown || sameDay
            timeShown = timeShown || sameTime
        }
        guard dayShown else { return giveUp("no picker shows the day") }
        guard timeShown else { return giveUp("no picker shows the time") }
        let press = button.pressReporting()
        note("pressed \(button.title ?? "Schedule"): \(press.detail)")
        return .scheduled(pressOK: press.ok)
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
    var identifier: String? { AXMenuNode.string(element, kAXIdentifierAttribute) }
    var children: [DialogNode] { AXMenuNode.childElements(element).map(AXDialogNode.init) }

    var date: Date? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? Date
    }

    func setDate(_ date: Date) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, date as CFDate) == .success
    }

    func press() -> Bool { pressReporting().ok }

    func pressReporting() -> (ok: Bool, detail: String) {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return (result == .success, result == .success ? "ok" : "AXError \(result.rawValue)")
    }

    var valueDescription: String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let value else { return "no value (AXError \(result.rawValue))" }
        if let date = value as? Date { return "date " + ISO8601DateFormatter().string(from: date) }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return "\(CFCopyTypeIDDescription(CFGetTypeID(value)) as String), settable \(settable.boolValue)"
    }
}
