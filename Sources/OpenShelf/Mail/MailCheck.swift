import AppKit
import ApplicationServices

/// A read-only look at Mail, for building the Mail helpers against Mail's real windows
/// (MAIL-PLAN.md spikes 1 and 2). It writes what it finds to a file and changes nothing:
/// no press, no key, and no message text. Only roles, identifiers, button and menu
/// titles, date pickers' dates and whether the menu items are enabled are written.
@MainActor
enum MailCheck {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenShelf/mail-check.txt")
    }

    /// Looks at Mail now and writes the file. Returns its location, or why it couldn't.
    static func run(now: Date = .now) -> Result<URL, CheckError> {
        guard let mail = MailMenu.running else { return .failure(.notRunning) }
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        var lines = ["Mail check, \(ISO8601DateFormatter().string(from: now)). Read only; no message text."]
        lines.append("Mail in front: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == MailMenu.bundleID ? "yes" : "no")")
        if let focused = AXMenuNode.element(app, kAXFocusedUIElementAttribute) {
            lines.append("Focused element: \(describe(focused))")
        }
        if let bar = MailMenu.menuBar() {
            for path in [MailMenu.send, MailMenu.archive, MailMenu.remindMeLater] {
                let name = path.joined(separator: " › ")
                if let item = MailMenu.find(path, in: bar) as? AXMenuNode {
                    lines.append("\(name): \(item.isEnabled ? "enabled" : "disabled"), shortcut \(shortcut(of: item.element))")
                } else {
                    lines.append("\(name): not found")
                }
            }
        }
        // Every window, front first, with its sheets (the Remind Me dialog is a sheet).
        let windows = MailHelpers.windows(pid: mail.processIdentifier)
        if let dialog = RemindDialog.find(in: windows) as? AXDialogNode {
            lines.append("Remind Me dialog: \(describe(dialog.element))")
            walk(dialog.element, depth: 0, into: &lines)
        } else {
            lines.append("Remind Me dialog: not found (no sheet or window with Cancel, Schedule and a date picker)")
        }
        for (index, window) in windows.enumerated() {
            guard let node = window as? AXDialogNode else { continue }
            lines.append("Window \(index + 1)\(index == 0 ? " (front)" : ""): \(describe(node.element))")
            walk(node.element, depth: 0, into: &lines)
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
            return .success(fileURL)
        } catch {
            return .failure(.cannotWrite)
        }
    }

    enum CheckError: Error, Equatable {
        case notRunning, noAccessibility, cannotWrite

        var message: String {
            switch self {
            case .notRunning: "Mail isn't running"
            case .noAccessibility: "OpenShelf needs Accessibility to look at Mail"
            case .cannotWrite: "Couldn't write the check file"
            }
        }
    }

    /// Roles that are written with what they show: a button's title, a date picker's date.
    /// Text fields and static text are never read.
    static func describe(_ element: AXUIElement) -> String {
        let role = AXMenuNode.string(element, kAXRoleAttribute) ?? "?"
        var parts = [role]
        if let subrole = AXMenuNode.string(element, kAXSubroleAttribute) { parts.append(subrole) }
        if let identifier = AXMenuNode.string(element, kAXIdentifierAttribute) { parts.append("id=\(identifier)") }
        if [kAXButtonRole, kAXPopUpButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXMenuButtonRole].contains(role),
           let title = AXMenuNode.string(element, kAXTitleAttribute) ?? AXMenuNode.string(element, kAXDescriptionAttribute) {
            parts.append("“\(title)”")
        }
        if role == "AXDateTimeArea" || role == "AXDateField" {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success, let value {
                if let date = value as? Date {
                    parts.append("value=\(ISO8601DateFormatter().string(from: date))")
                } else {
                    parts.append("value type=\(CFCopyTypeIDDescription(CFGetTypeID(value)) as String)")
                }
            } else {
                parts.append("no value")
            }
            parts.append("settable=\(isSettable(element))")
        }
        return parts.joined(separator: " ")
    }

    private static func walk(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 8, lines.count < 800 else { return }
        for child in AXMenuNode.childElements(element) {
            let role = AXMenuNode.string(child, kAXRoleAttribute) ?? ""
            // Message lists and bodies can be huge and hold mail; their insides are skipped.
            if ["AXTable", "AXOutline", "AXWebArea", "AXScrollArea", "AXTextArea", "AXTextField", "AXStaticText"].contains(role) {
                lines.append(String(repeating: "  ", count: depth + 1) + role + " (not read)")
                continue
            }
            lines.append(String(repeating: "  ", count: depth + 1) + describe(child))
            walk(child, depth: depth + 1, into: &lines)
        }
    }

    private static func isSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }

    /// A menu item's shortcut as Mail reports it, e.g. "⌘ + “↩”".
    private static func shortcut(of item: AXUIElement) -> String {
        let char = AXMenuNode.string(item, kAXMenuItemCmdCharAttribute)
        var glyph: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXMenuItemCmdGlyphAttribute as CFString, &glyph)
        var modifiers: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers)
        let charText = char.map { "char “\($0)” (U+\(String(format: "%04X", $0.unicodeScalars.first?.value ?? 0)))" } ?? "no char"
        let readable = Self.readable(char: char, modifiers: modifiers as? Int)
        return "\(readable) (\(charText), glyph \((glyph as? Int).map(String.init) ?? "none"), modifiers \((modifiers as? Int).map(String.init) ?? "none"))"
    }

    /// A menu item's shortcut as people write it: Accessibility's modifiers count up from
    /// ⌘ alone (0); 1 adds ⇧, 2 ⌥, 4 ⌃, and 8 means no ⌘. "⌘E" for char "E", modifiers 0.
    static func readable(char: String?, modifiers: Int?) -> String {
        guard let char, !char.isEmpty else { return "no shortcut" }
        let bits = modifiers ?? 0
        var keys = ""
        if bits & 4 != 0 { keys += "⌃" }
        if bits & 2 != 0 { keys += "⌥" }
        if bits & 1 != 0 { keys += "⇧" }
        if bits & 8 == 0 { keys += "⌘" }
        return keys + char
    }
}
