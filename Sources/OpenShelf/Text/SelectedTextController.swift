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
        var context: TextContext
        var location: NSPoint
    }

    private let wheel: WheelController
    private let relay: ClipboardRelay
    /// Adds a file to a shelf (⇧ held when choosing).
    var addToShelf: ([URL]) -> Void = { _ in }
    private(set) var history = TextHistory()
    private var session: Session?

    init(wheel: WheelController, relay: ClipboardRelay = ClipboardRelay(pasteboard: SystemTextPasteboard(), keys: CGEventKeySender())) {
        self.wheel = wheel
        self.relay = relay
    }

    /// Opens the text wheel for `text`, selected in `app`.
    func open(_ text: String, rich: RichText?, in app: NSRunningApplication, at location: NSPoint) {
        let canUndo = history.undoable(for: text, in: app.bundleIdentifier) != nil
        let context = TextContext(text: text, hasRichText: true, canUndo: canUndo)
        session = Session(text: text, rich: rich, app: app, context: context, location: location)
        show(group: nil, at: location)
    }

    /// The ⌘C fallback for apps whose selection Accessibility can't read.
    /// Waits for the shortcut's own keys to be let go first, so the app sees
    /// ⌘C and not ⌃⌥⌘C.
    func copySelection() async -> ClipboardRelay.Copied? {
        await waitForModifierRelease()
        return await relay.copySelection()
    }

    private func show(group: TextGroup?, at location: NSPoint?) {
        guard let session else { return }
        let items = TextWheel.items(for: session.context, group: group)
        let count = session.text.count
        wheel.presentForKeyboard(
            items: items,
            title: group?.title ?? "Text",
            summary: count == 1 ? "1 character" : "\(count) characters",
            hint: "Return replaces · ⌥ copies · ⇧ to shelf",
            at: location
        )
    }

    /// Runs a text wedge. `modifiers` are the keys held for it: ⌥ copies the
    /// result instead of replacing the selection, ⇧ saves it to a shelf.
    func perform(_ command: TextCommand, modifiers: NSEvent.ModifierFlags) {
        guard let session else { return }
        switch command {
        case .open(let group):
            show(group: group, at: nil)
        case .back:
            show(group: nil, at: nil)
        case .undo:
            guard let entry = history.undoable(for: session.text, in: session.app.bundleIdentifier) else { return }
            history.remove(entry)
            Task { await deliver(entry.original, fileExtension: "txt", modifiers: modifiers, recordsHistory: false) }
        case .tool(let tool):
            Task { await run(tool, on: session, modifiers: modifiers) }
        case .convert(let target):
            guard let source = session.context.dataFormat else { return }
            Task {
                await produce(fileExtension: target.fileExtension, modifiers: modifiers) {
                    try await TextConversion.convert(session.text, from: source, to: target, tools: .current)
                }
            }
        }
    }

    private func run(_ tool: TextTool, on session: Session, modifiers: NSEvent.ModifierFlags) async {
        if let result = tool.apply(to: session.text) {
            await deliver(result, fileExtension: "txt", modifiers: modifiers)
            return
        }
        switch tool {
        case .reindent:
            guard let ext = session.context.codeExtension else { return }
            await produce(fileExtension: ext, modifiers: modifiers) {
                guard let result = try await TextConversion.reindent(session.text, fileExtension: ext, tools: .current) else {
                    throw TextToolMessage.alreadyTidy
                }
                return result
            }
        case .toMarkdown:
            await produce(fileExtension: "md", modifiers: modifiers) {
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

    private func produce(fileExtension: String, modifiers: NSEvent.ModifierFlags, _ work: @escaping () async throws -> String) async {
        do {
            let result = try await work()
            await deliver(result, fileExtension: fileExtension, modifiers: modifiers)
        } catch let message as TextToolMessage {
            ToastController.shared.show(message.toast)
        } catch {
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Couldn’t change the text", subtitle: error.localizedDescription), for: .seconds(4))
        }
    }

    /// Puts `result` where the modifiers say: over the selection (the
    /// default), on the clipboard (⌥), or in a file on a shelf (⇧).
    private func deliver(_ result: String, fileExtension: String, modifiers: NSEvent.ModifierFlags, recordsHistory: Bool = true) async {
        guard let session else { return }
        switch TextDelivery(modifiers: modifiers) {
        case .copy:
            relay.pasteboard.writeText(result)
            ToastController.shared.show(Toast(systemImage: "doc.on.clipboard", title: "Copied"))
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
            guard await activate(session.app), selectionIsUnchanged(session) else {
                relay.pasteboard.writeText(result)
                ToastController.shared.show(Toast(systemImage: "doc.on.clipboard", title: "Copied instead", subtitle: "The selection changed, so nothing was replaced"), for: .seconds(3))
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

/// Where a text tool's result goes, from the keys held when it was chosen.
enum TextDelivery: Equatable {
    case replace
    case copy
    case shelf

    init(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.option) {
            self = .copy
        } else if modifiers.contains(.shift) {
            self = .shelf
        } else {
            self = .replace
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
