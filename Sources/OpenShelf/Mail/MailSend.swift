import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// ⌘↩ sends and ⇧⌘↩ sends then archives, in Mail (ROADMAP I5, MAIL-PLAN slice B).
/// Both press Message › Send by its title, so they don't depend on the App Shortcut.
/// Archive happens only when OpenShelf is sure which message the reply answers.
@MainActor
enum MailSend {
    static let sendShortcut = KeyCombo(keyCode: UInt32(kVK_Return), modifiers: [.command], keyName: "↩")
    static let sendAndArchiveShortcut = KeyCombo(keyCode: UInt32(kVK_Return), modifiers: [.command, .shift], keyName: "↩")

    /// A message selected in Mail's viewer: its Message-ID and subject (never its body).
    struct Selected: Equatable, Sendable {
        var id: String
        var subject: String
    }

    /// "Re: Re: Fwd: Lunch" and "lunch" are the same conversation.
    static func baseSubject(_ subject: String) -> String {
        var rest = subject.trimmingCharacters(in: .whitespaces)
        while let range = rest.range(of: #"^(re|fw|fwd|aw|sv|antw)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            rest.removeSubrange(range)
        }
        return rest.lowercased()
    }

    /// The message to archive after sending the reply titled `replyTitle`: the one message
    /// selected in the viewer, when its subject is the reply's. Nil when unsure.
    static func original(forReply replyTitle: String, selected: [Selected]) -> Selected? {
        guard selected.count == 1, let message = selected.first, !message.id.isEmpty else { return nil }
        let reply = baseSubject(replyTitle)
        guard !reply.isEmpty, reply == baseSubject(message.subject) else { return nil }
        return message
    }

    /// ⌘↩: Send, when Mail has it enabled (a message is being written). Otherwise nothing,
    /// as before.
    static func send() {
        guard let bar = MailMenu.menuBar(), let item = MailMenu.find(MailMenu.send, in: bar),
              mayPress(sendEnabled: item.isEnabled, mailHasFocus: MailMenu.hasKeyboardFocus()) else { return }
        _ = item.press()
    }

    /// Send is pressed only when Mail has it enabled and Mail itself has the keyboard: ⌘↩
    /// typed into a panel over Mail (Spotlight, Alfred) never sends a draft.
    static func mayPress(sendEnabled: Bool, mailHasFocus: Bool) -> Bool { sendEnabled && mailHasFocus }

    /// ⇧⌘↩: Send, then Archive the message the reply answers.
    static func sendAndArchive(scripting: MailScripting = AppleScriptMail()) {
        guard let mail = MailMenu.running, let bar = MailMenu.menuBar(),
              let sendItem = MailMenu.find(MailMenu.send, in: bar),
              mayPress(sendEnabled: sendItem.isEnabled, mailHasFocus: MailMenu.hasKeyboardFocus()) else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let compose = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return }
        let title = AXMenuNode.string(compose, kAXTitleAttribute) ?? ""
        let original = original(forReply: title, selected: scripting.selectedMessages())
        guard sendItem.press() else { return }
        guard let original else {
            toast("Sent, not archived", "Couldn't tell which message this answers")
            return
        }
        Task { @MainActor in
            // Archive only once the reply's window is gone (sent), and only the same message.
            guard await windowCloses(compose) else {
                toast("Not archived", "The message wasn't sent yet")
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard scripting.selectedMessages() == [original],
                  let archive = MailMenu.find(MailMenu.archive, in: MailMenu.menuBar() ?? []), archive.isEnabled, archive.press() else {
                toast("Sent, not archived", "The message isn't selected any more")
                return
            }
            toast("Sent and archived", original.subject)
        }
    }

    private static func windowCloses(_ window: AXUIElement) async -> Bool {
        for _ in 0..<50 {
            var role: CFTypeRef?
            // A closed window's element stops answering.
            if AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) != .success { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func toast(_ title: String, _ subtitle: String) {
        ToastController.shared.show(Toast(systemImage: "paperplane", title: title, subtitle: subtitle), for: .seconds(4))
    }
}

/// What the Mail helpers ask Mail through AppleScript. A protocol, so tests use a fake.
@MainActor
protocol MailScripting {
    func selectedMessages() -> [MailSend.Selected]
}

/// Mail's AppleScript: the viewer's selected messages' Message-IDs and subjects. Needs
/// Automation permission for Mail, asked the first time.
struct AppleScriptMail: MailScripting {
    func selectedMessages() -> [MailSend.Selected] {
        let source = """
        tell application id "com.apple.mail"
            set out to ""
            repeat with m in (selection as list)
                set out to out & (message id of m) & tab & (subject of m) & linefeed
            end repeat
            return out
        end tell
        """
        var error: NSDictionary?
        guard let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return MailSend.Selected(id: String(parts[0]), subject: String(parts[1]))
        }
    }
}
