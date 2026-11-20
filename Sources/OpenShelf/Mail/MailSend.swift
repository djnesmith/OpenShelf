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

    /// What ⌘↩ (and ⇧⌘↩) do with Mail as it is.
    enum Outcome: Equatable {
        case press
        /// No Message › Send: Mail shows it only while a message is being written
        /// (David's Check Mail, 2026-11-20: "not found" with the viewer in front).
        case notWriting
        /// Send is there but Mail has it off for this message.
        case sendOff
        /// A panel over Mail (Spotlight, Alfred) has the keyboard.
        case notMail

        /// The gray reason shown when nothing is sent; the shortcut is taken either way,
        /// so it never goes silently.
        var reason: String? {
            switch self {
            case .press: nil
            case .notWriting: "No message being written in front"
            case .sendOff: "Mail has Send off for this message right now"
            case .notMail: "Mail doesn't have the keyboard"
            }
        }
    }

    static func outcome(sendFound: Bool, sendEnabled: Bool, mailHasFocus: Bool) -> Outcome {
        guard sendFound else { return .notWriting }
        guard mailHasFocus else { return .notMail }
        return mayPress(sendEnabled: sendEnabled, mailHasFocus: mailHasFocus) ? .press : .sendOff
    }

    /// Mail's Send item now, and what ⌘↩ would do; each run goes to send.log.
    private static func check(_ keys: String) -> (Outcome, MenuNode?) {
        let item = MailMenu.menuBar().flatMap { MailMenu.find(MailMenu.send, in: $0) }
        let hasFocus = MailMenu.hasKeyboardFocus()
        let outcome = outcome(sendFound: item != nil, sendEnabled: item?.isEnabled ?? false, mailHasFocus: hasFocus)
        SnoozeLog.append(["\(keys): Send \(item == nil ? "not found" : (item!.isEnabled ? "enabled" : "disabled")), Mail has the keyboard: \(hasFocus), \(outcome)"], to: logURL)
        if let reason = outcome.reason { toast("Not sent", reason) }
        return (outcome, item)
    }

    static var logURL: URL {
        OpenShelfFiles.logs.appendingPathComponent("send.log")
    }

    /// ⌘↩: Send, when Mail has it enabled and the keyboard. Otherwise a short gray reason.
    static func send() {
        guard case (.press, let item?) = check("⌘↩") else { return }
        SnoozeLog.append(["⌘↩: pressed Send: \(item.press())"], to: logURL)
    }

    /// Send is pressed only when Mail has it enabled and Mail itself has the keyboard: ⌘↩
    /// typed into a panel over Mail (Spotlight, Alfred) never sends a draft.
    static func mayPress(sendEnabled: Bool, mailHasFocus: Bool) -> Bool { sendEnabled && mailHasFocus }

    /// ⇧⌘↩: Send, then Archive the message the reply answers.
    static func sendAndArchive(scripting: MailScripting = AppleScriptMail()) {
        guard let mail = MailMenu.running, case (.press, _?) = check("⇧⌘↩") else { return }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let compose = AXMenuNode.element(app, kAXFocusedWindowAttribute) else { return }
        let title = AXMenuNode.string(compose, kAXTitleAttribute) ?? ""
        Task { @MainActor in
            // Mail answers on the scripts' queue; what the key was pressed on is checked again
            // when the answer arrives: the same message in front, Send still on.
            let selected = await scripting.selectedMessages()
            guard let front = AXMenuNode.element(app, kAXFocusedWindowAttribute), CFEqual(front, compose),
                  let sendItem = MailMenu.menuBar().flatMap({ MailMenu.find(MailMenu.send, in: $0) }),
                  mayPress(sendEnabled: sendItem.isEnabled, mailHasFocus: MailMenu.hasKeyboardFocus()) else {
                toast("Not sent", "Mail changed while it answered")
                return
            }
            let original = original(forReply: title, selected: selected)
            guard sendItem.press() else { return }
            guard let original else {
                toast("Sent, not archived", "Couldn't tell which message this answers")
                return
            }
            // Archive only once the reply's window is gone (sent), and only the same message.
            guard await windowCloses(compose) else {
                toast("Not archived", "The message wasn't sent yet")
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            let now = await scripting.selectedMessages()
            guard now == [original],
                  let archive = MailMenu.find(MailMenu.archive, in: MailMenu.menuBar() ?? []), archive.isEnabled, archive.press() else {
                toast("Sent, not archived", "The message isn't selected any more")
                return
            }
            toast("Sent and archived", original.subject, for: MailHelpers.successToast)
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

    private static func toast(_ title: String, _ subtitle: String, for duration: Duration = MailHelpers.problemToast) {
        ToastController.shared.show(Toast(systemImage: "paperplane", title: title, subtitle: subtitle), for: duration)
    }
}

/// What the Mail helpers ask Mail through AppleScript. A protocol, so tests use a fake.
@MainActor
protocol MailScripting {
    /// Asked on the scripts' queue; a fake may answer at once.
    func selectedMessages() async -> [MailSend.Selected]
}

/// Mail's AppleScript: the viewer's selected messages' Message-IDs and subjects. Needs
/// Automation permission for Mail, asked the first time.
struct AppleScriptMail: MailScripting {
    func selectedMessages() async -> [MailSend.Selected] {
        let source = MailScripts.selectedMessages
        guard let text = await MailScript.run("selected messages", source).text else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return MailSend.Selected(id: String(parts[0]), subject: String(parts[1]))
        }
    }
}
