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

    /// The system-wide secure-input flag, and the pid the session reports
    /// for it, for the log only. The flag is often left on (loginwindow after
    /// unlocking), and the reported pid follows the frontmost app, so neither
    /// says whether the focused field is a password field; the field's own
    /// subrole does.
    nonisolated static var secureInputDiagnostics: String {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
        return "secure input flag \(IsSecureEventInputEnabled() ? "on" : "off"), reported pid \(pid.map(String.init) ?? "none")"
    }

    /// The selection in app `pid`'s focused element.
    static func read(pid: pid_t) -> SelectedTextRead {
        guard isTrusted else { return .notPermitted }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Electron apps only build their accessibility tree when asked to.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return .unavailable }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)
        if string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            TextLog.passwordField(pid: pid)
            return .secure
        }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value) {
        case .success:
            guard let text = value as? String else { return .unavailable }
            return text.isEmpty ? .nothingSelected : .text(text)
        default:
            return .unavailable
        }
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
