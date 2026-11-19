import AppKit

/// Runs the text wheel: holds the selection the shortcut found, opens the
/// wheel and its sub-wheels, runs the chosen tool, and puts the result back.
@MainActor
final class SelectedTextController {
    /// The selection being worked on, from the moment the wheel opens.
    struct Session {
        var text: String
        /// The formatted version, when ⌘C already brought one (the fallback route).
        var rich: RichText?
        var app: NSRunningApplication
        var strategy: TextAppStrategy
        /// The reader that found the text, which decides how it is written back.
        var source: TextReader
        var context: TextContext
        var location: NSPoint
    }

    private let wheel: WheelController
    private let relay: ClipboardRelay
    /// Adds a file to a shelf (⇧ held when choosing).
    var addToShelf: ([URL]) -> Void = { _ in }
    private(set) var history = TextHistory()
    private var session: Session?

    /// The formatted version from the last ⌘C read, for To Markdown.
    private var lastRich: RichText?

    init(wheel: WheelController, relay: ClipboardRelay? = nil) {
        self.wheel = wheel
        var relay = relay ?? ClipboardRelay(pasteboard: SystemTextPasteboard(), keys: CGEventKeySender())
        relay.willBorrow = { ClipboardWatcher.shared.willBorrow() }
        relay.didRestore = { ClipboardWatcher.shared.didRestore() }
        self.relay = relay
    }

    /// Finds the text in `app` with its strategy's readers and opens the
    /// wheel, or says why not.
    func route(in app: NSRunningApplication) async -> HotkeyRoute {
        lastRich = nil
        let strategy = TextAppStrategy.for(bundleID: app.bundleIdentifier)
        return await HotkeyRoute.choose(
            frontmostBundleID: app.bundleIdentifier,
            isSecureInputOn: AccessibilityText.isSecureInputOn,
            strategy: strategy
        ) { reader in
            await self.read(reader, in: app)
        }
    }

    private func read(_ reader: TextReader, in app: NSRunningApplication) async -> SelectedTextRead {
        switch reader {
        case .accessibility:
            return AccessibilityText.read(pid: app.processIdentifier)
        case .copyShortcut:
            guard AccessibilityText.isTrusted else { return .notPermitted }
            // The shortcut's own keys go up first, so the app sees ⌘C, not ⌃⌥⌘C.
            await waitForModifierRelease()
            guard let copied = await relay.copySelection() else { return .unavailable }
            lastRich = copied.rich
            return .text(copied.text)
        case .recentClipboard:
            return ClipboardWatcher.shared.recentText().map(SelectedTextRead.text) ?? .unavailable
        case .emacsClient:
            switch await EmacsClient.read() {
            case .region(let text): return .text(text)
            case .noRegion: return .nothingSelected
            default: return .unavailable
            }
        }
    }

    /// Opens the text wheel for `text`, found in `app` by `source`.
    func open(_ text: String, from source: TextReader, in app: NSRunningApplication, at location: NSPoint) {
        let canUndo = history.undoable(for: text, in: app.bundleIdentifier) != nil
        let context = TextContext(text: text, hasRichText: source != .recentClipboard, canUndo: canUndo)
        let strategy = TextAppStrategy.for(bundleID: app.bundleIdentifier)
        session = Session(text: text, rich: lastRich, app: app, strategy: strategy, source: source, context: context, location: location)
        show(group: nil, at: location)
    }

    private func show(group: TextGroup?, at location: NSPoint?) {
        guard let session else { return }
        let items = TextWheel.items(for: session.context, group: group)
        let count = session.text.count
        wheel.presentForKeyboard(
            items: items,
            title: group?.title ?? TextWheel.title(for: session.text, from: session.source),
            summary: count == 1 ? "1 character" : "\(count) characters",
            hint: session.strategy.hint(for: session.source),
            at: location,
            searchCandidates: TextWheel.searchCandidates(for: session.context, from: group)
        )
    }

    /// Runs a text wedge. `modifiers` are the keys held for it: ⌥ copies the
    /// result instead of replacing the selection, ⇧ saves it to a shelf.
    func perform(_ command: TextCommand, modifiers: NSEvent.ModifierFlags) {
        guard let session else { return }
        switch command {
        case .open(let group):
            show(group: group, at: nil)
        case .back(let group):
            show(group: group, at: nil)
        case .undo:
            guard let entry = history.undoable(for: session.text, in: session.app.bundleIdentifier) else { return }
            history.remove(entry)
            Task { await deliver(entry.original, done: "Original", fileExtension: "txt", modifiers: modifiers, recordsHistory: false) }
        case .tool(let tool):
            Task { await run(tool, on: session, modifiers: modifiers) }
        case .edit:
            edit(session, modifiers: modifiers.subtracting(.shift))
        case .convert(let target):
            guard let source = session.context.dataFormat else { return }
            Task {
                await produce(done: command.doneTitle, fileExtension: target.fileExtension, modifiers: modifiers) {
                    try await TextConversion.convert(session.text, from: source, to: target, tools: .current)
                }
            }
        }
    }

    /// Opens the Edit window. ⌘↩ there puts the text where a tool's result
    /// would go (⌥ held on the wedge copies it); nothing is written to disk.
    private func edit(_ session: Session, modifiers: NSEvent.ModifierFlags) {
        let appName = session.app.localizedName ?? "the app"
        let delivery = TextDelivery(modifiers: modifiers, strategy: session.strategy, source: session.source)
        let opened = VimEditorWindow.shared.open(
            session.text,
            title: session.source == .recentClipboard ? "Edit Copied Text" : "Edit Text from \(appName)",
            destination: delivery == .replace ? "back into \(appName)" : "on the clipboard",
            near: session.location,
            onFinish: { [weak self] result in
                guard let self else { return }
                self.session = session
                Task {
                    // Minutes may have passed, so only a selection read back
                    // unchanged is replaced; anything else is copied.
                    await self.deliver(result, done: TextCommand.edit.doneTitle, fileExtension: "txt", modifiers: modifiers, mustConfirmSelection: true)
                    // Copying leaves OpenShelf in front, with no window of its own.
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                        session.app.activate()
                    }
                }
            },
            onCancel: { [weak self] in
                self?.session = nil
                session.app.activate()
            }
        )
        if !opened {
            ToastController.shared.show(Toast(systemImage: "character.cursor.ibeam", title: "Already editing", subtitle: "Finish (⌘↩) or cancel (⌘W) that edit first"))
        }
    }

    private func run(_ tool: TextTool, on session: Session, modifiers: NSEvent.ModifierFlags) async {
        let done = TextCommand.tool(tool).doneTitle
        if let result = tool.apply(to: session.text) {
            await deliver(result, done: done, fileExtension: "txt", modifiers: modifiers)
            return
        }
        switch tool {
        case .reindent:
            guard let ext = session.context.codeExtension else { return }
            await produce(done: done, fileExtension: ext, modifiers: modifiers) {
                guard let result = try await TextConversion.reindent(session.text, fileExtension: ext, tools: .current) else {
                    throw TextToolMessage.alreadyTidy
                }
                return result
            }
        case .toMarkdown:
            await produce(done: done, fileExtension: "md", modifiers: modifiers) {
                guard let rich = try await self.richText(for: session) else { throw TextToolMessage.noFormatting }
                return try await TextConversion.toMarkdown(rich, tools: .current)
            }
        default:
            return
        }
    }

    /// The selection's formatted version: the one ⌘C already brought, or a
    /// fresh ⌘C in the app (Accessibility only gives plain text).
    private func richText(for session: Session) async throws -> RichText? {
        if let rich = session.rich { return rich }
        guard await activate(session.app) else { return nil }
        return await relay.copySelection()?.rich
    }

    private func produce(done: String, fileExtension: String, modifiers: NSEvent.ModifierFlags, _ work: @escaping () async throws -> String) async {
        do {
            let result = try await work()
            await deliver(result, done: done, fileExtension: fileExtension, modifiers: modifiers)
        } catch let message as TextToolMessage {
            ToastController.shared.show(message.toast)
        } catch {
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Couldn’t change the text", subtitle: error.localizedDescription), for: .seconds(4))
        }
    }

    /// Puts `result` where the app and the modifiers say: over the selection,
    /// on the clipboard (⌥, and always in a terminal), or in a file on a shelf (⇧).
    private func deliver(_ result: String, done: String, fileExtension: String, modifiers: NSEvent.ModifierFlags, recordsHistory: Bool = true, mustConfirmSelection: Bool = false) async {
        guard let session else { return }
        switch TextDelivery(modifiers: modifiers, strategy: session.strategy, source: session.source) {
        case .copy:
            relay.pasteboard.writeText(result)
            if recordsHistory {
                history.record(original: session.text, result: result, bundleID: session.app.bundleIdentifier)
            }
            ToastController.shared.show(Toast(systemImage: "doc.on.clipboard", title: "\(done) and copied"))
        case .shelf:
            do {
                addToShelf([try TextFiles.save(result, fileExtension: fileExtension)])
            } catch {
                ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Couldn’t save the text", subtitle: error.localizedDescription))
            }
        case .replace:
            guard result != session.text else {
                ToastController.shared.show(TextToolMessage.unchanged.toast)
                return
            }
            if session.source == .emacsClient {
                await replaceInEmacs(result, done: done, recordsHistory: recordsHistory)
                return
            }
            var activated = false
            if !session.app.isTerminated { activated = await activate(session.app) }
            guard activated, mustConfirmSelection ? Self.canReplace(session, now: Self.currentSelection(of: session)) : selectionIsUnchanged(session) else {
                relay.pasteboard.writeText(result)
                let reason = session.app.isTerminated ? "\(session.app.localizedName ?? "The app") quit" : "The selection changed"
                ToastController.shared.show(Toast(systemImage: "doc.on.clipboard", title: "Copied instead", subtitle: "\(reason), so nothing was replaced"), for: .seconds(3))
                return
            }
            await waitForModifierRelease()
            await relay.paste(result)
            if recordsHistory {
                history.record(original: session.text, result: result, bundleID: session.app.bundleIdentifier)
            }
        }
        self.session = nil
    }

    /// Replaces the region through emacsclient, as one change Emacs can undo.
    private func replaceInEmacs(_ result: String, done: String, recordsHistory: Bool) async {
        guard let session else { return }
        let outcome = await EmacsClient.replace(session.text, with: result)
        TextLog.emacsWrite(outcome)
        if outcome == .replaced {
            if recordsHistory {
                history.record(original: session.text, result: result, bundleID: session.app.bundleIdentifier)
            }
        } else {
            relay.pasteboard.writeText(result)
            let reason = outcome == .changed ? "The region changed in Emacs, so nothing was replaced" : "Emacs didn’t answer, so nothing was replaced"
            ToastController.shared.show(Toast(systemImage: "doc.on.clipboard", title: "\(done) and copied instead", subtitle: reason), for: .seconds(3))
        }
        self.session = nil
    }

    /// What is selected in the session's app now, for the Edit window's check.
    private static func currentSelection(of session: Session) -> SelectedTextRead {
        guard AccessibilityText.isTrusted else { return .notPermitted }
        return AccessibilityText.read(pid: session.app.processIdentifier)
    }

    /// Whether Edit may paste over the selection: only when it reads back as
    /// the same text, and secure input is off. A field that is gone, a caret
    /// with nothing selected or a password field all copy instead. Apps read
    /// with ⌘C can't be read back, so they are trusted as tools are; copied
    /// text and terminals (⌃ held) paste at the cursor, as the tools do.
    static func canReplace(_ session: Session, now: SelectedTextRead, isSecureInputOn: Bool = AccessibilityText.isSecureInputOn) -> Bool {
        guard !isSecureInputOn else { return false }
        if session.strategy.isCopyOnly(from: session.source) { return true }
        if case .text(let text) = now { return text == session.text }
        return session.source == .copyShortcut && now == .unavailable
    }

    /// Whether the app still has the same text selected, where Accessibility
    /// can tell; a paste must never land on a different selection.
    private func selectionIsUnchanged(_ session: Session) -> Bool {
        guard AccessibilityText.isTrusted, let now = AccessibilityText.currentSelection(pid: session.app.processIdentifier) else { return true }
        return now == session.text
    }

    /// Brings the app back in front (the keyboard wheel may have activated
    /// OpenShelf) and waits up to half a second for it.
    private func activate(_ app: NSRunningApplication) async -> Bool {
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            app.activate()
            try? await Task.sleep(for: .milliseconds(10))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// Up to half a second for ⌃⌥⇧⌘ to be let go, so a posted ⌘C or ⌘V
    /// isn't read with the shortcut's keys still down.
    private func waitForModifierRelease() async {
        for _ in 0..<50 {
            if NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Outcomes that are not failures but still need saying.
enum TextToolMessage: Error {
    case alreadyTidy
    case unchanged
    case noFormatting

    var toast: Toast {
        switch self {
        case .alreadyTidy: Toast(systemImage: "checkmark", title: "Already tidy")
        case .unchanged: Toast(systemImage: "checkmark", title: "Nothing to change")
        case .noFormatting: Toast(systemImage: "textformat", title: "No formatting to convert", subtitle: "The app copied plain text only")
        }
    }
}

/// Text results saved for a shelf (⇧), in Application Support so they
/// outlive the temporary folder.
enum TextFiles {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenShelf/Text", isDirectory: true)
    }

    static func save(_ text: String, fileExtension: String, in folder: URL = folder, now: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = OutputNaming.uniqueURL(in: folder, baseName: "Text \(formatter.string(from: now))", pathExtension: fileExtension)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
