import Foundation

/// A tool on the text wheel.
enum TextTool: CaseIterable, Hashable, Sendable {
    case trim
    case cleanUp
    case reindent
    case toMarkdown
    case dedent
    case indent
    case outdent
    case tabsSpaces
    case trimLines
    case straightenQuotes

    var title: String {
        switch self {
        case .trim: "Trim"
        case .cleanUp: "Clean Up"
        case .reindent: "Re-indent"
        case .toMarkdown: "To Markdown"
        case .dedent: "Dedent"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .tabsSpaces: "Tabs ↔ Spaces"
        case .trimLines: "Trim Lines"
        case .straightenQuotes: "Straight Quotes"
        }
    }

    var systemImage: String {
        switch self {
        case .trim: "scissors"
        case .cleanUp: "sparkles"
        case .reindent: "text.alignleft"
        case .toMarkdown: "number"
        case .dedent: "arrow.left.to.line"
        case .indent: "increase.indent"
        case .outdent: "decrease.indent"
        case .tabsSpaces: "arrow.left.arrow.right"
        case .trimLines: "line.3.horizontal"
        case .straightenQuotes: "quote.opening"
        }
    }

    /// Tools done in memory, with no file and no external process.
    var isPureSwift: Bool { ![.reindent, .toMarkdown].contains(self) }

    /// Runs a pure-Swift tool; nil for the ones that need a converter.
    func apply(to text: String) -> String? {
        switch self {
        case .trim: TextTransforms.trim(text)
        case .cleanUp: TextTransforms.cleanUp(text)
        case .dedent: TextTransforms.dedent(text)
        case .indent: TextTransforms.indent(text)
        case .outdent: TextTransforms.outdent(text)
        case .tabsSpaces:
            Self.indentsWithTabs(text) ? TextTransforms.tabsToSpaces(text) : TextTransforms.spacesToTabs(text)
        case .trimLines: TextTransforms.trimLines(text)
        case .straightenQuotes: TextTransforms.straightenQuotes(text)
        case .reindent, .toMarkdown: nil
        }
    }

    /// Whether any line is indented with a tab, which decides the direction of Tabs ↔ Spaces.
    static func indentsWithTabs(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { $0.prefix { $0 == " " || $0 == "\t" }.contains("\t") }
    }
}

/// The sub-wheels a text wheel wedge can open.
enum TextGroup: Hashable, Sendable {
    case convert
    case more

    var title: String {
        switch self {
        case .convert: "Convert"
        case .more: "More"
        }
    }
}

/// What a wedge on the text wheel does.
enum TextCommand: Hashable, Sendable {
    case tool(TextTool)
    case convert(DataTextFormat)
    case open(TextGroup)
    /// Back from a sub-wheel to the first wheel.
    case back
    /// Puts the original back over what OpenShelf wrote (⌥ copies it instead).
    case undo
}

/// What is known about a selection when its wheel is built.
struct TextContext: Equatable {
    var dataFormat: DataTextFormat?
    var codeExtension: String?
    /// The selection may have an HTML or RTF version for To Markdown to read.
    var hasRichText: Bool
    var canUndo: Bool

    init(text: String, hasRichText: Bool, canUndo: Bool) {
        dataFormat = TextSniffer.dataFormat(of: text)
        codeExtension = TextSniffer.codeExtension(for: text)
        self.hasRichText = hasRichText
        self.canUndo = canUndo
    }
}

/// The wedges of the text wheel and its sub-wheels. A wheel shows 7 wedges
/// before it pages, so each list here stays at 7 or fewer.
enum TextWheel {
    static func items(for context: TextContext, group: TextGroup? = nil) -> [WheelItem] {
        switch group {
        case nil:
            var commands: [TextCommand] = []
            if context.canUndo { commands.append(.undo) }
            commands += [.tool(.trim), .tool(.cleanUp)]
            if context.codeExtension != nil { commands.append(.tool(.reindent)) }
            if context.dataFormat != nil { commands.append(.open(.convert)) }
            // Formatted prose, not data or code, is what To Markdown is for.
            if context.hasRichText, context.dataFormat == nil, context.codeExtension == nil { commands.append(.tool(.toMarkdown)) }
            commands.append(.open(.more))
            return commands.map(WheelItem.text)
        case .convert:
            let targets = DataTextFormat.allCases.filter { $0 != context.dataFormat }
            return targets.map { WheelItem.text(.convert($0)) } + [WheelItem.text(.back)]
        case .more:
            let tools: [TextTool] = [.dedent, .indent, .outdent, .tabsSpaces, .trimLines, .straightenQuotes]
            return tools.map { WheelItem.text(.tool($0)) } + [WheelItem.text(.back)]
        }
    }
}

extension WheelItem {
    static func text(_ command: TextCommand) -> WheelItem {
        switch command {
        case .tool(let tool):
            WheelItem(command: .text(command), title: tool.title, systemImage: tool.systemImage)
        case .convert(let format):
            WheelItem(command: .text(command), title: format.title, systemImage: nil)
        case .open(let group):
            WheelItem(command: .text(command), title: "\(group.title) ▸", systemImage: group == .convert ? "arrow.triangle.2.circlepath" : "ellipsis.circle")
        case .back:
            WheelItem(command: .text(command), title: "Back", systemImage: "chevron.backward")
        case .undo:
            WheelItem(command: .text(command), title: "Undo", systemImage: "arrow.uturn.backward")
        }
    }
}
