import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Unsubscribe and block in one step (MAIL-PLAN slice G), through Mail's own right-click
/// menu on the selected message ("Unsubscribe", "Block Sender": Mail 16's
/// `MessageViewerContextMenu.loctable`). Mail does the unsubscribing, so OpenShelf opens no
/// link and reads no header. It asks first, every time.
@MainActor
enum MailUnsubscribe {
    static let shortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_U), modifiers: [.control, .option], keyName: "U")
    static let unsubscribeTitle = "Unsubscribe"
    static let blockTitle = "Block Sender"

    /// What the step will do with the items Mail's menu offers.
    enum Plan: Equatable {
        case unsubscribeAndBlock
        /// Mail offers no Unsubscribe for this message (no list header): block only.
        case blockOnly
        /// Neither item: nothing to do.
        case nothing
    }

    static func plan(offered items: [MenuNode]) -> Plan {
        let unsubscribe = MailMenu.findAnywhere(unsubscribeTitle, in: items)?.isEnabled == true
        let block = MailMenu.findAnywhere(blockTitle, in: items)?.isEnabled == true
        switch (unsubscribe, block) {
        case (true, true): return .unsubscribeAndBlock
        case (false, true): return .blockOnly
        default: return .nothing
        }
    }

    /// Whether the message confirmed is still the one selected: exactly one, the same Message-ID.
    static func stillSame(asked: [MailSend.Selected], now: [MailSend.Selected]) -> Bool {
        asked.count == 1 && now == asked
    }

    /// The confirm question for `plan` and the sender's address.
    static func question(for plan: Plan, sender: String) -> String? {
        switch plan {
        case .unsubscribeAndBlock: "Unsubscribe from \(sender) and block it?"
        case .blockOnly: "Mail offers no unsubscribe for this message. Block \(sender)?"
        case .nothing: nil
        }
    }

    /// The one selected message's sender, its right-click menu, a confirm, then Mail's items.
    static func run(scripting: MailScripting = AppleScriptMail()) {
        guard let mail = MailMenu.running, let row = selectedRow(pid: mail.processIdentifier) else {
            tell("Nothing done", "Select one message in Mail's list first")
            return
        }
        let sender = scripting.selectedSenders().first ?? "this sender"
        // The message asked about; after the question it must still be the one selected.
        let asked = scripting.selectedMessages()
        guard let items = openMenu(on: row) else {
            tell("Nothing done", "Mail's message menu didn't open")
            return
        }
        let plan = plan(offered: items)
        cancelMenu(on: row)
        guard let question = question(for: plan, sender: sender) else {
            tell("Nothing done", "Mail offers neither Unsubscribe nor Block Sender here")
            return
        }
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: plan == .blockOnly ? "Block" : "Unsubscribe and Block")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard stillSame(asked: asked, now: scripting.selectedMessages()) else {
            tell("Nothing done", "A different message is selected now")
            return
        }
        mail.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            for title in plan == .unsubscribeAndBlock ? [unsubscribeTitle, blockTitle] : [blockTitle] {
                guard stillSame(asked: asked, now: scripting.selectedMessages()) else {
                    tell("Stopped", "A different message is selected now")
                    return
                }
                guard let row = selectedRow(pid: mail.processIdentifier), let items = openMenu(on: row),
                      let item = MailMenu.findAnywhere(title, in: items), item.isEnabled, item.press() else {
                    if let row = selectedRow(pid: mail.processIdentifier) { cancelMenu(on: row) }
                    tell("Stopped", "Mail's “\(title)” wasn't there")
                    return
                }
                // Mail may ask about the unsubscribe itself; give it time before the next item.
                try? await Task.sleep(for: .milliseconds(600))
            }
            tell(plan == .blockOnly ? "Blocked" : "Unsubscribed and blocked", sender)
        }
    }

    /// The selected row of Mail's message list, when exactly one is selected.
    static func selectedRow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard var list = AXMenuNode.element(app, kAXFocusedUIElementAttribute) else { return nil }
        while let role = AXMenuNode.string(list, kAXRoleAttribute), !["AXTable", "AXOutline"].contains(role) {
            guard let parent = AXMenuNode.element(list, kAXParentAttribute) else { return nil }
            list = parent
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXSelectedRowsAttribute as CFString, &selected) == .success,
              let rows = selected as? [AXUIElement], rows.count == 1 else { return nil }
        return rows[0]
    }

    /// Opens the row's right-click menu and returns its items, or nil if none appears.
    private static func openMenu(on row: AXUIElement) -> [MenuNode]? {
        guard AXUIElementPerformAction(row, kAXShowMenuAction as CFString) == .success else { return nil }
        for _ in 0..<10 {
            if let menu = AXMenuNode.childElements(row).first(where: { AXMenuNode.string($0, kAXRoleAttribute) == kAXMenuRole }) {
                return AXMenuNode.childElements(menu).map(AXMenuNode.init)
            }
            usleep(50_000)
        }
        return nil
    }

    /// Closes the row's menu without choosing anything.
    private static func cancelMenu(on row: AXUIElement) {
        for menu in AXMenuNode.childElements(row) where AXMenuNode.string(menu, kAXRoleAttribute) == kAXMenuRole {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
    }

    private static func tell(_ title: String, _ subtitle: String) {
        ToastController.shared.show(Toast(systemImage: "hand.raised", title: title, subtitle: subtitle), for: .seconds(4))
    }
}

extension MailScripting {
    /// The selected messages' senders, through Mail's AppleScript.
    func selectedSenders() -> [String] {
        let source = """
        tell application id "com.apple.mail"
            set out to ""
            repeat with m in (selection as list)
                set out to out & (extract address from (sender of m)) & linefeed
            end repeat
            return out
        end tell
        """
        guard let text = MailScript.run("selected senders", source).text else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}
