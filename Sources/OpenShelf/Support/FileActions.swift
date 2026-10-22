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

    /// Asks for a destination folder, then moves the files into it. Name clashes
    /// are reported rather than overwritten. Returns where files went and how many
    /// moved, or nil when cancelled.
    @discardableResult
    static func moveWithPrompt(_ urls: [URL]) -> (destination: URL, movedCount: Int)? {
        guard let destination = chooseDestination(for: urls, verb: "Move") else { return nil }

        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.moveItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        report(failures, verb: "moved")
        return (destination, urls.count - failures.count)
    }

    /// Asks for a destination folder, as Move does, then copies the files there;
    /// the originals stay put. A name already taken gets a Finder-style number
    /// ("Report 2.pdf"), so copying into the same folder makes a duplicate.
    @discardableResult
    static func copyWithPrompt(_ urls: [URL]) -> (destination: URL, copiedCount: Int)? {
        guard let destination = chooseDestination(for: urls, verb: "Copy") else { return nil }
        let result = copy(urls, into: destination)
        report(result.failures, verb: "copied")
        return (destination, result.copied.count)
    }

    /// Copies each item into `destination` with its attributes and dates (and
    /// folders with everything inside), never over an existing file.
    static func copy(_ urls: [URL], into destination: URL) -> (copied: [URL], failures: [String]) {
        var copied: [URL] = []
        var failures: [String] = []
        for url in urls {
            let pathExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
            let target = OutputNaming.uniqueURL(in: destination, baseName: url.deletingPathExtension().lastPathComponent, pathExtension: pathExtension)
            do {
                try FileManager.default.copyItem(at: url, to: target)
                copied.append(target)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (copied, failures)
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
