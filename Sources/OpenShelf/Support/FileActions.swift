import AppKit

/// File operations shared by the Actions wheel and shelf menus.
@MainActor
enum FileActions {
    static func open(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Puts the files themselves on the clipboard, so pasting in Finder copies them.
    static func copyFiles(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    static func copyPaths(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        copyText(urls.map(\.path).joined(separator: "\n"), to: pasteboard)
    }

    /// The file names with their extensions ("Report.pdf"), one a line, in
    /// the order Copy Path uses.
    static func copyNames(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        copyText(urls.map(\.lastPathComponent).joined(separator: "\n"), to: pasteboard)
    }

    static func copyText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        service.perform(withItems: urls)
    }

    /// Opens the files' folders in iTerm2 when it's installed (a new window at
    /// each folder), otherwise in Terminal.
    static func openInTerminal(_ urls: [URL]) {
        guard let terminal = TerminalApp.preferred?.url else { return }
        let folders = Set(urls.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isDirectory ? url : url.deletingLastPathComponent()
        })
        NSWorkspace.shared.open(Array(folders), withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Asks for a destination folder, then moves the files into it, asking what
    /// to do about each name already taken there (see `transfer`). Returns where
    /// files went and how many moved, or nil when cancelled.
    @discardableResult
    static func moveWithPrompt(_ urls: [URL]) -> (destination: URL, movedCount: Int, moves: [URL: URL])? {
        guard let destination = chooseDestination(for: urls, verb: "Move") else { return nil }
        let result = transfer(urls, into: destination, operation: .move, prompt: askAboutConflict)
        report(result.failures, verb: "moved")
        return (destination, result.done.count, result.moves)
    }

    /// The same as `moveWithPrompt`, copying instead: the originals stay put.
    @discardableResult
    static func copyWithPrompt(_ urls: [URL]) -> (destination: URL, copiedCount: Int)? {
        guard let destination = chooseDestination(for: urls, verb: "Copy") else { return nil }
        let result = transfer(urls, into: destination, operation: .copy, prompt: askAboutConflict)
        report(result.failures, verb: "copied")
        return (destination, result.done.count)
    }

    enum Transfer: Sendable {
        case move, copy
    }

    /// What to do when the name is taken at the destination.
    enum ConflictChoice: Equatable, Sendable {
        /// Put the existing item in the Trash, then this one in its place.
        case overwrite
        /// Give this one a Finder-style number: "Report 2.pdf".
        case keepBoth
        /// Leave this one where it is and the existing one alone.
        case skip
    }

    struct ConflictDecision: Equatable, Sendable {
        var choice: ConflictChoice
        /// Use the same choice for the rest of this move or copy.
        var applyToAll = false
    }

    /// Asked about one name clash: the item's name, the destination folder,
    /// and whether to offer "Apply to all" (more clashes follow).
    typealias ConflictPrompt = (_ name: String, _ destination: URL, _ offersApplyToAll: Bool) -> ConflictDecision

    /// Moves or copies each item into `destination`. A copy keeps attributes,
    /// dates and quarantine, and takes folders whole (FileManager). When a name
    /// is taken, `prompt` decides; Overwrite sends the existing item (a folder
    /// whole, never merged) to the Trash through `trash`, so it can be got back.
    /// An item already in `destination` is left as it is when moving and
    /// duplicated when copying, without asking.
    static func transfer(
        _ urls: [URL],
        into destination: URL,
        operation: Transfer,
        prompt: ConflictPrompt,
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> (done: [URL], skipped: Int, failures: [String], moves: [URL: URL]) {
        let fileManager = FileManager.default
        func isAlreadyThere(_ url: URL) -> Bool {
            url.deletingLastPathComponent().standardizedFileURL.path == destination.standardizedFileURL.path
        }
        func numbered(_ url: URL) -> URL {
            OutputNaming.uniqueURL(in: destination, baseName: url.deletingPathExtension().lastPathComponent, pathExtension: url.pathExtension.isEmpty ? nil : url.pathExtension)
        }
        let clashes = urls.filter { !isAlreadyThere($0) && fileManager.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) }.count

        var done: [URL] = []
        var skipped = 0
        var failures: [String] = []
        var moves: [URL: URL] = [:]
        var remembered: ConflictChoice?
        var asked = 0
        for url in urls {
            var target = destination.appendingPathComponent(url.lastPathComponent)
            do {
                if isAlreadyThere(url) {
                    // Moving onto itself changes nothing.
                    guard operation == .copy else { continue }
                    target = numbered(url)
                } else if fileManager.fileExists(atPath: target.path) {
                    let choice: ConflictChoice
                    if let remembered {
                        choice = remembered
                    } else {
                        asked += 1
                        let decision = prompt(url.lastPathComponent, destination, clashes - asked > 0)
                        choice = decision.choice
                        if decision.applyToAll { remembered = choice }
                    }
                    switch choice {
                    case .skip:
                        skipped += 1
                        continue
                    case .keepBoth:
                        target = numbered(url)
                    case .overwrite:
                        try trash(target)
                    }
                }
                switch operation {
                case .move:
                    try fileManager.moveItem(at: url, to: target)
                    moves[url.standardizedFileURL] = target
                case .copy:
                    try fileManager.copyItem(at: url, to: target)
                }
                done.append(target)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (done, skipped, failures, moves)
    }

    /// Finder's question: Keep Both (the default, Return), Overwrite, or
    /// Cancel (Esc), with "Apply to all" when more clashes follow.
    private static func askAboutConflict(_ name: String, in destination: URL, offersApplyToAll: Bool) -> ConflictDecision {
        let alert = NSAlert()
        alert.messageText = "“\(name)” already exists in “\(destination.lastPathComponent)”."
        alert.informativeText = "Overwrite moves the existing one to the Trash. Keep Both gives the new one a number."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Overwrite")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        if offersApplyToAll {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Apply to all"
        }
        NSApp.activate()
        let response = alert.runModal()
        let choice: ConflictChoice = switch response {
        case .alertFirstButtonReturn: .keepBoth
        case .alertSecondButtonReturn: .overwrite
        default: .skip
        }
        return ConflictDecision(choice: choice, applyToAll: alert.suppressionButton?.state == .on)
    }

    /// Move's and Copy's folder picker, starting where the first file is.
    private static func chooseDestination(for urls: [URL], verb: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = urls.count == 1 ? "\(verb) “\(urls[0].lastPathComponent)” to…" : "\(verb) \(urls.count) Files to…"
        panel.prompt = verb
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        NSApp.activate()
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private static func report(_ failures: [String], verb: String) {
        guard !failures.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = failures.count == 1 ? "A file couldn’t be \(verb)" : "\(failures.count) files couldn’t be \(verb)"
        alert.informativeText = failures.joined(separator: "\n")
        alert.runModal()
    }

    /// Total size of the regular files among `urls`, or nil if it includes a folder.
    static func totalFileSize(of urls: [URL]) -> Int64? {
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { return nil }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

/// The terminal app folders open in: iTerm2 when it's installed, else Terminal.
enum TerminalApp {
    static let iTermIdentifier = "com.googlecode.iterm2"
    static let terminalIdentifier = "com.apple.Terminal"

    /// Looked up once; installing iTerm2 later shows after a relaunch.
    static let preferred: (url: URL, name: String)? = choose { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

    static func choose(_ lookup: (String) -> URL?) -> (url: URL, name: String)? {
        if let iTerm = lookup(iTermIdentifier) { return (iTerm, "iTerm") }
        return lookup(terminalIdentifier).map { ($0, "Terminal") }
    }

    /// "iTerm" or "Terminal", for labels and messages.
    static var name: String { preferred?.name ?? "Terminal" }
}
