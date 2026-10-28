import Foundation

/// A free tool that adds formats macOS can't handle itself, as presented in
/// Settings → Extra Formats and in messages that point there.
enum ExtraTool: String, CaseIterable, Identifiable, Sendable {
    case ffmpeg
    case libreOffice
    case pandoc

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ffmpeg: "ffmpeg"
        case .libreOffice: "LibreOffice"
        case .pandoc: "Pandoc"
        }
    }

    /// One short line on what installing it adds: these formats as outputs,
    /// and for ffmpeg also as files that can be converted. Pandoc adds the
    /// markup formats (`PandocConversion.markupFormats`) and converts
    /// Markdown and Word its own way.
    var unlocks: String {
        switch self {
        case .ffmpeg: "MP3, OGG, WebP, MKV, WebM, AVI and WMV"
        case .libreOffice: "PowerPoint, ODP, XLS and ODS"
        case .pandoc: "LaTeX, Typst, reST, AsciiDoc and Org, and Pandoc’s Markdown and Word conversions"
        }
    }

    /// The Homebrew alternative to installing from Settings.
    var homebrewCommand: String {
        switch self {
        case .ffmpeg: "brew install ffmpeg"
        case .libreOffice: "brew install --cask libreoffice"
        case .pandoc: "brew install pandoc"
        }
    }

    /// The second line of the toast after an install.
    var installedConfirmation: String {
        switch self {
        case .ffmpeg: "MP3, WebP, MKV… are now on the wheel"
        case .libreOffice: "PowerPoint, XLS… are now on the wheel"
        case .pandoc: "Markdown and Word convert with Pandoc"
        }
    }

    func path(in tools: ExternalTools) -> URL? {
        switch self {
        case .ffmpeg: tools.ffmpeg
        case .libreOffice: tools.libreOffice
        case .pandoc: tools.pandoc
        }
    }

    func isInstalled(in tools: ExternalTools) -> Bool {
        path(in: tools) != nil
    }

    /// `tools` as if this one were installed, to ask the catalog what it would
    /// add. The placeholder path is never run; ffprobe stays as it is so the
    /// question never starts a process.
    func assumedInstalled(in tools: ExternalTools) -> ExternalTools {
        var tools = tools
        let placeholder = URL(fileURLWithPath: "/nonexistent/\(rawValue)")
        switch self {
        case .ffmpeg: tools.ffmpeg = placeholder
        case .libreOffice: tools.libreOffice = placeholder
        case .pandoc: tools.pandoc = placeholder
        }
        return tools
    }
}

/// A tool Settings → Extra Formats lists: one it installs, or one Homebrew does.
enum MissingTool: Equatable, Sendable {
    case extra(ExtraTool)
    case commandLine(CommandLineTool)

    /// ffmpeg and LibreOffice first, as Settings lists them.
    static var allCases: [MissingTool] {
        ExtraTool.allCases.map(MissingTool.extra) + CommandLineTool.allCases.map(MissingTool.commandLine)
    }

    var name: String {
        switch self {
        case .extra(let tool): tool.name
        case .commandLine(let tool): tool.name
        }
    }

    /// The toast's second line: where to install it.
    var installHint: String {
        switch self {
        case .extra: MissingToolAdvice.installHint
        case .commandLine(let tool): tool.installCommand
        }
    }

    func isInstalled(in tools: ExternalTools) -> Bool {
        switch self {
        case .extra(let tool): tool.isInstalled(in: tools)
        case .commandLine(let tool): tool.isInstalled(in: tools)
        }
    }

    func assumedInstalled(in tools: ExternalTools) -> ExternalTools {
        switch self {
        case .extra(let tool): tool.assumedInstalled(in: tools)
        case .commandLine(let tool): tool.assumedInstalled(in: tools)
        }
    }
}

/// What to say when a missing tool is the reason a wheel has little to offer.
/// Pure decisions, so they can be tested without a drag.
enum MissingToolAdvice {
    /// The second line of every "needs …" message.
    static let installHint = "Install it in Settings → Extra Formats"

    /// The tool whose absence leaves these files with nothing but ZIP on the
    /// Convert wheel, when installing it would offer real conversions. Nil
    /// for folders, unknown files, Keynote decks and mixes that share no
    /// format anyway: their ZIP wheel is all there is.
    static func blockingTool(for urls: [URL], formats: [OutputFormat], tools: ExternalTools) -> MissingTool? {
        guard !urls.isEmpty, onlyArchives(formats) else { return nil }
        return MissingTool.allCases.first { tool in
            !tool.isInstalled(in: tools)
                && !onlyArchives(ConversionCatalog.formats(for: urls, tools: tool.assumedInstalled(in: tools)))
        }
    }

    /// A wheel of ZIP, tar and 7z only: packing the file, not converting it.
    static func onlyArchives(_ formats: [OutputFormat]) -> Bool {
        !formats.isEmpty && formats.allSatisfy(ConversionCatalog.archiveFormats.contains)
    }

    /// The tool whose absence leaves these files with an empty Tools wheel
    /// (a Python file without ruff), or nil.
    static func blockingTool(forToolsWheel urls: [URL], tools: ExternalTools) -> MissingTool? {
        guard !urls.isEmpty, FileTool.available(for: urls, tools: tools).isEmpty else { return nil }
        return MissingTool.allCases.first { tool in
            !tool.isInstalled(in: tools) && !FileTool.available(for: urls, tools: tool.assumedInstalled(in: tools)).isEmpty
        }
    }

    /// "MKV needs ffmpeg", shown instead of a ZIP-only wheel. Names only the
    /// files that need the tool (not the MP4 dragged along with an MKV). One
    /// line each, like every toast.
    static func toast(for urls: [URL], needing tool: MissingTool, tools: ExternalTools) -> Toast {
        let blocked = urls.filter { onlyArchives(ConversionCatalog.formats(for: [$0], tools: tools)) }
        let names = uniqueNames(of: blocked.isEmpty ? urls : blocked)
        var title = "These files need \(tool.name)"
        if !names.contains("") {
            if names.count == 1 {
                title = "\(names[0]) needs \(tool.name)"
            } else if names.count == 2 {
                title = "\(names[0]) and \(names[1]) need \(tool.name)"
            }
        }
        if title.count > 28 {
            title = "These files need \(tool.name)"
        }
        return Toast(systemImage: "puzzlepiece.extension", title: title, subtitle: tool.installHint)
    }

    /// A one-time note for audio and video that convert natively but would get
    /// MP3, MKV, WebM and more with ffmpeg.
    static func moreFormatsHint(for urls: [URL], tools: ExternalTools) -> String? {
        guard tools.ffmpeg == nil, !urls.isEmpty else { return nil }
        let isNativeMedia = urls.allSatisfy { url in
            let kind = FileKind(url: url)
            return (kind == .audio || kind == .video) && MediaFormats.isAVFoundationReadable(url)
        }
        return isNativeMedia ? "More formats in Settings → Extra Formats" : nil
    }

    /// How a format is known to people: "PowerPoint", "WebM", "MKV"; empty
    /// for a file without an extension.
    static func displayName(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "ppt", "pptx": "PowerPoint"
        case "webm": "WebM"
        case "opus": "Opus"
        case "oga": "OGG"
        default: ext.uppercased()
        }
    }

    private static func uniqueNames(of urls: [URL]) -> [String] {
        var names: [String] = []
        for url in urls {
            let name = displayName(forExtension: url.resolvingSymlinksInPath().pathExtension)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
