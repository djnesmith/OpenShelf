import AppKit
import ApplicationServices

/// A menu item as Accessibility shows it. A protocol, so tests use a fake menu.
@MainActor
protocol MenuNode {
    var title: String { get }
    var isEnabled: Bool { get }
    /// The items of its menu or submenu.
    var children: [MenuNode] { get }
    func press() -> Bool
}

/// Mail's menu items the Mail helpers use, found by their exact titles (Mail 16,
/// `MainMenu.loctable`). Nothing is pressed blind: a missing or renamed item is reported.
@MainActor
enum MailMenu {
    static let bundleID = "com.apple.mail"

    static let remindMeLater = ["Message", "Remind Me", "Remind Me Later…"]
    static let archive = ["Message", "Archive"]
    static let send = ["Message", "Send"]

    /// Every item the snooze needs, for the check before it runs.
    static let snoozePaths = [remindMeLater, archive]

    /// The item at `path` (menu bar title, then item titles) in `bar`.
    static func find(_ path: [String], in bar: [MenuNode]) -> MenuNode? {
        var level = bar
        var found: MenuNode?
        for title in path {
            guard let next = level.first(where: { $0.title == title }) else { return nil }
            found = next
            level = next.children
        }
        return found
    }

    /// The paths in `paths` that `bar` lacks, as "Message › Remind Me › Remind Me Later…".
    static func missing(_ paths: [[String]], in bar: [MenuNode]) -> [String] {
        paths.filter { find($0, in: bar) == nil }.map { $0.joined(separator: " › ") }
    }

    /// The running Mail, if any.
    static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Mail's menu bar through Accessibility, or nil when Mail isn't running or
    /// OpenShelf may not read it.
    static func menuBar() -> [MenuNode]? {
        guard let mail = running else { return nil }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let bar = AXMenuNode.element(app, kAXMenuBarAttribute) else { return nil }
        return AXMenuNode.childElements(bar).map(AXMenuNode.init)
    }
}

/// A menu bar item or menu item in another app, read through Accessibility.
@MainActor
struct AXMenuNode: MenuNode {
    let element: AXUIElement

    var title: String { Self.string(element, kAXTitleAttribute) ?? "" }

    var isEnabled: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// A menu bar item or menu item holds one AXMenu, whose children are the items.
    var children: [MenuNode] {
        Self.childElements(element).flatMap { menu in Self.childElements(menu).map(AXMenuNode.init) }
    }

    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
