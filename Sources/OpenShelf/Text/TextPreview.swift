import Foundation

/// What the live preview beside the text wheel shows for a wedge (ROADMAP C13). Pure:
/// it never touches the source app or the clipboard.
enum TextPreview: Equatable {
    /// The text as it would be after the tool runs.
    case result(String)
    /// A tool that doesn't change the text, or isn't run for a preview: a short note.
    case note(String)
    /// Nothing to show (a sub-wheel, Back, a snippet).
    case none

    /// The preview for `command` on `text`. Tools that would run another program
    /// (Re-indent, To Markdown) or read the clipboard (Markdown Link) are described, not run;
    /// Generate tools show an example.
    static func make(for command: TextCommand, text: String) -> TextPreview {
        switch command {
        case .tool(let tool):
            switch tool {
            case .count: return .note("Counts the characters, words and lines, and shows them; the text stays as it is.")
            case .md5, .sha1, .sha256: return .note("Copies the \(tool.title) of the text; the text stays as it is.")
            case .jwt: return .note("Copies the token's header and payload; the text stays as it is.")
            case .reindent: return .note("Re-indents with the code tool for this language when chosen.")
            case .toMarkdown: return .note("Turns the formatted text into Markdown when chosen.")
            case .markdownLink: return .note("Makes a Markdown link from this text and the link you copied, when chosen.")
            case .uuid, .timestamp, .loremIpsum, .password:
                return tool.apply(to: text).map { .result($0) } ?? .none
            default:
                guard let result = tool.apply(to: text) else { return .none }
                return result == text ? .note("Nothing to change.") : .result(result)
            }
        case .convert(let format):
            return .note("Converts the text to \(format.title) when chosen.")
        case .undo, .edit, .open, .back, .snippet, .snippetGroup, .snippetBack:
            return .none
        }
    }

    /// What the pane shows: the text now, or a tool's result; a note only where it says
    /// something the text can't (Count, Hash, a tool that runs another program).
    struct Pane: Equatable {
        /// "Now", or "After <tool>".
        var caption: String
        var note: String?
        var body: String
        /// The line to scroll to (0-based).
        var line: Int
    }

    /// The pane for the highlighted wedge (`command` nil: nothing highlighted). Anything
    /// that isn't a one-shot tool shows the text as it is now (David, 2026-11-20: "it
    /// should have the text in it for all text selections or clipboard editing").
    static func pane(for command: TextCommand?, title: String?, text: String) -> Pane {
        let now = Pane(caption: "Now", note: nil, body: text, line: 0)
        guard let command else { return now }
        switch make(for: command, text: text) {
        case .result(let result):
            return Pane(caption: "After \(title ?? "this")", note: nil, body: result, line: max(firstChangedLine(from: text, to: result) - 2, 0))
        case .note(let note):
            var pane = now
            pane.note = title.map { "\($0): \(note)" } ?? note
            return pane
        case .none:
            return now
        }
    }

    /// The line where `result` first differs from `original` (0-based), to scroll to; 0
    /// when they start alike all the way or differ on the first line.
    static func firstChangedLine(from original: String, to result: String) -> Int {
        let old = original.split(separator: "\n", omittingEmptySubsequences: false)
        let new = result.split(separator: "\n", omittingEmptySubsequences: false)
        for index in 0..<min(old.count, new.count) where old[index] != new[index] { return index }
        return min(old.count, new.count) < new.count ? min(old.count, new.count) : 0
    }
}
