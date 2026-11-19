import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The Mail helpers (ROADMAP I4, MAIL-PLAN.md). Slice A: one shortcut, live only while
/// Mail is in front, opens the snooze prompt; the time chosen goes to Mail's own Remind
/// Me, through its menu by exact title. No wheel in Mail.
@MainActor
final class MailHelpers {
    static let shared = MailHelpers()

    /// Not yet decided by David: the prompt's shortcut. Default ⌃⌥S; another can be stored here.
    static let promptShortcutKey = "MailPromptShortcut"
    static let defaultPromptShortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option], keyName: "S")
    /// Not yet decided by David: quick filing and copying a message link, until the single
    /// keys (v, l) exist. ⌃⌥M and ⌃⌥K, while Mail is in front.
    static let moveShortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: [.control, .option], keyName: "M")
    static let linkShortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option], keyName: "K")
    /// Archive after Remind Me: only for Mail without its "Move to “Remind Me”" setting,
    /// which can't be read (it isn't in Mail's preference files). David has it on, so off.
    static let archiveAfterRemindKey = "MailSnoozeArchives"
    /// ⌘↩ sends and ⇧⌘↩ sends then archives (David: "i would like command - enter to always
    /// work"). On unless turned off here.
    static let sendKeysKey = "MailSendKeys"

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var promptShortcut: KeyCombo {
        defaults.data(forKey: Self.promptShortcutKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? Self.defaultPromptShortcut
    }

    var archivesAfterRemind: Bool { defaults.bool(forKey: Self.archiveAfterRemindKey) }

    var sendKeys: Bool { defaults.object(forKey: Self.sendKeysKey) as? Bool ?? true }

    /// Watches which app is in front, so the shortcut exists only while Mail is.
    func start() {
        GlobalHotKey.mail.onPress = { [weak self] in self?.showPrompt() }
        GlobalHotKey.mailSend.onPress = { MailSend.send() }
        GlobalHotKey.mailSendAndArchive.onPress = { MailSend.sendAndArchive() }
        GlobalHotKey.mailMove.onPress = { MailFiling.showPicker() }
        GlobalHotKey.mailLink.onPress = { MailLinks.copyLink() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontAppChanged(to: app?.bundleIdentifier) }
        }
        frontAppChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Registers the shortcut while Mail is in front, and only then. While the prompt is
    /// open, OpenShelf is in front and the shortcut stays off.
    func frontAppChanged(to bundleID: String?) {
        MailKeyTap.shared.update(front: bundleID)
        let listen = Self.shouldListen(front: bundleID)
        if listen {
            GlobalHotKey.mail.register(promptShortcut)
            GlobalHotKey.mailMove.register(Self.moveShortcut)
            GlobalHotKey.mailLink.register(Self.linkShortcut)
        } else {
            GlobalHotKey.mail.unregister()
            GlobalHotKey.mailMove.unregister()
            GlobalHotKey.mailLink.unregister()
        }
        if listen, sendKeys {
            GlobalHotKey.mailSend.register(MailSend.sendShortcut)
            GlobalHotKey.mailSendAndArchive.register(MailSend.sendAndArchiveShortcut)
        } else {
            GlobalHotKey.mailSend.unregister()
            GlobalHotKey.mailSendAndArchive.unregister()
        }
    }

    static func shouldListen(front bundleID: String?) -> Bool { bundleID == MailMenu.bundleID }

    func showPrompt() {
        // Checked first, so the prompt doesn't open over a compose window or with no message.
        if let problem = Self.problem(with: MailMenu.menuBar()) {
            ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Can't snooze", subtitle: problem), for: .seconds(4))
            return
        }
        SnoozePrompt.shared.show { [weak self] date in self?.snooze(until: date) }
    }

    /// Why the snooze can't run in Mail as it is now, or nil when it can.
    static func problem(with bar: [MenuNode]?) -> String? {
        guard let bar else { return "OpenShelf can't read Mail's menus (Accessibility)" }
        let missing = MailMenu.missing(MailMenu.snoozePaths, in: bar)
        if !missing.isEmpty { return "Mail's menu has changed: no \(missing.joined(separator: ", "))" }
        guard MailMenu.find(MailMenu.remindMeLater, in: bar)?.isEnabled == true else { return "Select a message in Mail's list first" }
        return nil
    }

    /// The menu bar's Check Mail: writes what OpenShelf sees in Mail (MailCheck) and says where.
    static func writeCheck() {
        switch MailCheck.run() {
        case .success(let url):
            ToastController.shared.show(Toast(systemImage: "envelope", title: "Checked Mail", subtitle: url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")), for: .seconds(5))
        case .failure(let error):
            ToastController.shared.show(Toast(systemImage: "envelope", title: "Couldn't check Mail", subtitle: error.message), for: .seconds(4))
        }
    }

    /// Mail's Remind Me at `date`, then Archive when that setting is on.
    func snooze(until date: Date) {
        guard let mail = MailMenu.running else { return }
        mail.activate()
        Task { @MainActor in
            // Mail takes back the front and its message list before its menu is used.
            try? await Task.sleep(for: .milliseconds(250))
            guard let bar = MailMenu.menuBar(), Self.problem(with: bar) == nil,
                  let remind = MailMenu.find(MailMenu.remindMeLater, in: bar), remind.press() else {
                ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Can't snooze", subtitle: Self.problem(with: MailMenu.menuBar()) ?? "Remind Me Later… didn't open"), for: .seconds(4))
                return
            }
            guard let window = await Self.waitForRemindWindow(pid: mail.processIdentifier) else {
                ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Can't snooze", subtitle: "Mail's Remind Me window didn't appear"), for: .seconds(4))
                return
            }
            switch RemindDialog.fill(AXDialogNode(element: window), with: date) {
            case .reminded:
                if archivesAfterRemind, let archive = MailMenu.find(MailMenu.archive, in: MailMenu.menuBar() ?? []) {
                    try? await Task.sleep(for: .milliseconds(300))
                    _ = archive.press()
                }
                ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Snoozed", subtitle: SnoozeTime.describe(date, calendar: .current)))
            case .cancelled(let reason):
                ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Not snoozed", subtitle: "Mail's Remind Me window: \(reason). Menu bar › Check Mail writes what OpenShelf sees."), for: .seconds(6))
            }
        }
    }

    /// Mail's Remind Me window: a sheet on its front window, or a window of its own, that
    /// has a "Remind Me" button. Waits up to two seconds.
    static func waitForRemindWindow(pid: pid_t) async -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        for _ in 0..<20 {
            var candidates: [AXUIElement] = []
            if let front = AXMenuNode.element(app, kAXFocusedWindowAttribute) {
                candidates.append(front)
                candidates += AXMenuNode.childElements(front).filter { AXMenuNode.string($0, kAXRoleAttribute) == kAXSheetRole }
            }
            if let window = candidates.reversed().first(where: { hasRemindButton($0, depth: 0) }) { return window }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func hasRemindButton(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 6 else { return false }
        return AXMenuNode.childElements(element).contains { child in
            (AXMenuNode.string(child, kAXRoleAttribute) == kAXButtonRole && AXMenuNode.string(child, kAXTitleAttribute) == RemindDialog.remindTitle)
                || hasRemindButton(child, depth: depth + 1)
        }
    }
}
