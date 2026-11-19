import os

/// What the shortcut decided for the frontmost app, in the unified log, so a
/// "nothing selected" can be traced to Accessibility or to ⌘C. Never logs the text.
/// Read with: log show --last 1h --predicate 'subsystem == "com.djnesmith.OpenShelf"'
enum TextLog {
    static let logger = Logger(subsystem: "com.djnesmith.OpenShelf", category: "text")

    static func route(_ route: HotkeyRoute, app: String?) {
        let app = app ?? "unknown"
        let readers = TextAppStrategy.for(bundleID: app).readers.map { "\($0)" }.joined(separator: ", ")
        switch route {
        case .finder: logger.info("shortcut in \(app, privacy: .public): Finder")
        case .text(let text, let reader): logger.info("shortcut in \(app, privacy: .public): \(text.count) characters via \(String(describing: reader), privacy: .public)")
        case .askForAccessibility: logger.info("shortcut in \(app, privacy: .public): Accessibility not allowed")
        // Notice, not info, so the system log keeps it for the next report.
        case .secureInput:
            let diagnostics = AccessibilityText.secureInputDiagnostics
            logger.notice("shortcut in \(app, privacy: .public): refused, password field focused; \(diagnostics, privacy: .public)")
        case .nothing: logger.info("shortcut in \(app, privacy: .public): no text from \(readers, privacy: .public)")
        }
    }

    static func passwordField(pid: pid_t) {
        logger.notice("focused element in pid \(pid, privacy: .public) is a password field (AXSecureTextField)")
    }

    static func emacsWrite(_ outcome: EmacsClient.Outcome) {
        logger.info("emacsclient replace: \(String(describing: outcome), privacy: .public)")
    }
}
