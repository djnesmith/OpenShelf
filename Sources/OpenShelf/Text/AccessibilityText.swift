import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the frontmost app's selected text through Accessibility.
@MainActor
enum AccessibilityText {
    /// Caps each call, so an app that has stopped answering can't freeze the wheel.
    static let messagingTimeout: Float = 0.25

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "OpenShelf would like to control this computer" prompt,
    /// which opens Privacy & Security → Accessibility. macOS shows it at most
    /// once; after that this only reports the current state.
    @discardableResult
    static func requestTrust() -> Bool {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read as a global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// The app that has secure input on (a password field, Terminal's Secure
    /// Keyboard Entry), if any. The flag is system-wide and is often left on
    /// by an app in the background (loginwindow after unlocking, a browser's
    /// password field), so only the app being read or written to counts.
    static var secureInputPID: pid_t? {
        guard IsSecureEventInputEnabled(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? NSNumber else { return nil }
        return pid.int32Value
    }

    /// Whether `pid` itself has secure input on.
    static func holdsSecureInput(_ pid: pid_t) -> Bool { secureInputPID == pid }

    /// The selection in app `pid`'s focused element.
    static func read(pid: pid_t) -> SelectedTextRead {
        guard isTrusted else { return .notPermitted }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Electron apps only build their accessibility tree when asked to.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return .unavailable }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)
        if string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return .secure }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value) {
        case .success:
            guard let text = value as? String else { return .unavailable }
            return text.isEmpty ? .nothingSelected : .text(text)
        default:
            return .unavailable
        }
    }

    /// The text selected now in app `pid`, or nil when it can't be read.
    /// Checked just before pasting, so a result never lands somewhere else.
    static func currentSelection(pid: pid_t) -> String? {
        if case .text(let text) = read(pid: pid) { return text }
        return nil
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
