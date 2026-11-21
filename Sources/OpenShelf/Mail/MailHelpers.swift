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
        GlobalHotKey.mailLink.onPress = { Task { await MailLinks.copyLink() } }
        GlobalHotKey.mailUnsubscribe.onPress = { MailUnsubscribe.run() }
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
            GlobalHotKey.mailUnsubscribe.register(MailUnsubscribe.shortcut)
        } else {
            GlobalHotKey.mail.unregister()
            GlobalHotKey.mailMove.unregister()
            GlobalHotKey.mailLink.unregister()
            GlobalHotKey.mailUnsubscribe.unregister()
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

    /// How long the Mail helpers' toasts stay: a plain success goes quickly (David,
    /// 2026-11-20: "the toast stays on too long"); anything to read stays longer.
    static let successToast: Duration = .milliseconds(1500)
    static let problemToast: Duration = .seconds(4)

    func showPrompt() {
        // Checked first, so the prompt doesn't open over a compose window or with no message.
        if let problem = Self.problem(with: MailMenu.menuBar()) {
            ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Can't snooze", subtitle: problem), for: .seconds(4))
            return
        }
        // Where the list was, for after the snooze (the next message) or Esc (back there).
        let place = MailListPlace.capture()
        SnoozePrompt.shared.show(onChoose: { [weak self] date in self?.snooze(until: date, from: place) },
                                 onCancel: { place?.restore() })
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

    /// Mail's Remind Me at `date`, then Archive when that setting is on. Every run writes
    /// its steps to SnoozeLog (no message text).
    func snooze(until date: Date, from place: MailListPlace? = nil) {
        guard let mail = MailMenu.running else { return }
        mail.activate()
        Task { @MainActor in
            var log = ["snooze to \(ISO8601DateFormatter().string(from: date))"]
            @MainActor func tell(_ title: String, _ subtitle: String, for duration: Duration = MailHelpers.problemToast) {
                log.append("toast: \(title): \(subtitle)")
                SnoozeLog.append(log)
                ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: title, subtitle: subtitle), for: duration)
            }
            // Mail takes back the front and its message list before its menu is used.
            try? await Task.sleep(for: .milliseconds(250))
            guard let bar = MailMenu.menuBar(), Self.problem(with: bar) == nil,
                  let remind = MailMenu.find(MailMenu.remindMeLater, in: bar), remind.press() else {
                tell("Can't snooze", Self.problem(with: MailMenu.menuBar()) ?? "Remind Me Later… didn't open")
                return
            }
            guard let dialog = await Self.waitForDialog(pid: mail.processIdentifier, seconds: 4) else {
                // Late after all: cancelled, so nothing is left half done.
                let late = await Self.waitForDialog(pid: mail.processIdentifier, seconds: 1)
                if let late { log.append("late dialog, Cancel: \(RemindDialog.cancel(late))") }
                tell("Can't snooze", late == nil ? "Mail's dialog didn't appear" : "Mail's dialog came late; cancelled")
                return
            }
            log.append("dialog: \(dialog.role)")
            switch RemindDialog.fill(dialog, with: date, note: { log.append($0) }) {
            case .scheduled:
                // Schedule was pressed, so "Not snoozed" is never said from here on.
                let closed = await Self.waitForDialogToClose(pid: mail.processIdentifier, seconds: 3)
                log.append("dialog closed: \(closed)")
                guard closed else {
                    tell("Not sure it snoozed", "Mail's dialog is still open", for: .seconds(5))
                    return
                }
                if archivesAfterRemind, let archive = MailMenu.find(MailMenu.archive, in: MailMenu.menuBar() ?? []) {
                    try? await Task.sleep(for: .milliseconds(300))
                    log.append("archive: \(archive.press())")
                }
                tell("Snoozed", "Until " + SnoozeTime.describe(date, calendar: .current), for: MailHelpers.successToast)
                await place?.selectNext()
            case .cancelled(let reason):
                tell("Not snoozed", reason, for: .seconds(6))
            }
        }
    }

    /// Mail's windows, front first, as dialog nodes.
    static func windows(pid: pid_t) -> [DialogNode] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var elements: [AXUIElement] = []
        if let front = AXMenuNode.element(app, kAXFocusedWindowAttribute) { elements.append(front) }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let all = value as? [AXUIElement] {
            elements += all.filter { window in !elements.contains { CFEqual($0, window) } }
        }
        return elements.map(AXDialogNode.init)
    }

    /// Polls Mail's windows and their sheets for the Remind Me dialog.
    static func waitForDialog(pid: pid_t, seconds: Double) async -> DialogNode? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let dialog = RemindDialog.find(in: windows(pid: pid)) { return dialog }
            try? await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        return nil
    }

    /// True once no Remind Me dialog is left in Mail.
    static func waitForDialogToClose(pid: pid_t, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if RemindDialog.find(in: windows(pid: pid)) == nil { return true }
            try? await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        return false
    }
}

/// The snooze's steps, appended to ~/Library/Logs/OpenShelf/snooze.log: what was found,
/// each picker's role and value, which buttons were pressed and how that went. No
/// message text. Kept under about 256 KB.
enum SnoozeLog {
    static var fileURL: URL {
        OpenShelfFiles.logs.appendingPathComponent("snooze.log")
    }

    static func append(_ lines: [String], to url: URL = fileURL, now: Date = .now) {
        let stamp = ISO8601DateFormatter().string(from: now)
        let entry = lines.map { "\(stamp) \($0)" }.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: url)) ?? Data()
        if data.count > 256_000 { data = data.suffix(128_000) }
        data.append(Data(entry.utf8))
        try? data.write(to: url, options: .atomic)
    }
}

/// The text wheel's preview steps (ROADMAP C13), appended to
/// ~/Library/Logs/OpenShelf/preview.log: the text's source, the wedge's title, and
/// whether the pane was shown, where, or why not. Never the text. A line the same as
/// the one before is skipped.
@MainActor
enum PreviewLog {
    static var fileURL: URL {
        OpenShelfFiles.logs.appendingPathComponent("preview.log")
    }
    private static var last = ""

    static func note(_ line: String, to url: URL = fileURL) {
        guard line != last else { return }
        last = line
        SnoozeLog.append([line], to: url)
    }
}

/// The viewer's message list as it was when the snooze prompt opened: after a snooze the
/// list gets the keyboard on the next message (David, 2026-11-21: "after b and the snooze
/// has been accepted the focus should go to the next message if there is one"); after Esc
/// it goes back to where it was. Only for Mail's main viewer; a message window: nothing.
/// Logs counts and roles only.
@MainActor
struct MailListPlace {
    let app: AXUIElement
    let viewer: AXUIElement
    let selected: [Int]
    let rows: Int
    let focused: AXUIElement?

    static func capture() -> MailListPlace? {
        guard let mail = MailMenu.running else { return nil }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let viewer = AXMenuNode.element(app, kAXFocusedWindowAttribute), MailKeys.isMainViewer(AXDialogNode(element: viewer)),
              let list = AXSelectableList.inViewer(viewer) else {
            KeysLog.note("snooze: not from the viewer's list; focus left to Mail afterwards")
            return nil
        }
        return MailListPlace(app: app, viewer: viewer, selected: list.selectedRows, rows: list.rows.count,
                             focused: AXMenuNode.element(app, kAXFocusedUIElementAttribute))
    }

    /// After the snooze: up to 1.5 s for the snoozed rows to leave, then the row that took
    /// their place (else the one above) is selected, the list gets the keyboard, and both
    /// are read back.
    func selectNext() async {
        var list = AXSelectableList.inViewer(viewer)
        for _ in 0..<6 {
            if let count = list?.rows.count, count <= rows - selected.count { break }
            try? await Task.sleep(for: .milliseconds(250))
            list = AXSelectableList.inViewer(viewer)
        }
        guard let list else { KeysLog.note("snooze: no message list afterwards"); return }
        let focusRole = AXMenuNode.element(app, kAXFocusedUIElementAttribute).flatMap { AXMenuNode.string($0, kAXRoleAttribute) } ?? "none"
        guard let target = MailKeys.rowAfterSnooze(selected: selected, rowsBefore: rows, rowsAfter: list.rows.count) else {
            KeysLog.note("snooze: rows \(rows) → \(list.rows.count), focus \(focusRole); no next message")
            return
        }
        AXUIElementPerformAction(viewer, kAXRaiseAction as CFString)
        _ = list.select([target])
        AXUIElementSetAttributeValue(list.list, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(150))
        let landed = list.selectedRows == [target]
        let inList = MailKeys.isInside(AXMenuNode.element(app, kAXFocusedUIElementAttribute), list.list,
                                      parent: { AXMenuNode.element($0, kAXParentAttribute) }, same: { CFEqual($0, $1) })
        KeysLog.note("snooze: rows \(rows) → \(list.rows.count), focus was \(focusRole); next message selected \(landed), list has the keyboard \(inList)")
        if !landed || !inList {
            ToastController.shared.show(Toast(systemImage: "envelope.badge.clock", title: "Snoozed; next message not selected",
                                              subtitle: "Click the list or press j"), for: .seconds(4))
        }
    }

    /// Esc in the prompt: the same rows selected again if the list still has them, and the
    /// keyboard back on what had it.
    func restore() {
        NSRunningApplication.runningApplications(withBundleIdentifier: MailMenu.bundleID).first?.activate()
        let list = AXSelectableList.inViewer(viewer)
        if let list, list.rows.count == rows, list.selectedRows != selected, selected.allSatisfy({ $0 < rows }) { _ = list.select(selected) }
        if let focused { AXUIElementSetAttributeValue(focused, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainActor.assumeIsolated {
                let now = AXMenuNode.element(app, kAXFocusedUIElementAttribute)
                let back = if let now, let focused { CFEqual(now, focused) } else { false }
                let same = AXSelectableList.inViewer(viewer)?.selectedRows == selected
                KeysLog.note("snooze cancelled: focus back \(back), same selection \(same)")
            }
        }
    }
}
