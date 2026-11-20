import AppKit
import Testing
@testable import OpenShelf

/// The live preview beside the text wheel (ROADMAP C13).
@MainActor
struct TextPreviewTests {
    @Test func pureToolsShowTheirResult() {
        #expect(TextPreview.make(for: .tool(.trim), text: "  hi  ") == .result("hi"))
        #expect(TextPreview.make(for: .tool(.sortAZ), text: "b\na") == .result("a\nb"))
        #expect(TextPreview.make(for: .tool(.trim), text: "hi") == .note("Nothing to change."))
    }

    /// Tools that report, run another program or read the clipboard are described, not run.
    @Test func otherToolsAreDescribed() {
        for command: TextCommand in [.tool(.count), .tool(.sha256), .tool(.jwt), .tool(.reindent), .tool(.toMarkdown), .tool(.markdownLink), .convert(.json)] {
            guard case .note = TextPreview.make(for: command, text: "x") else {
                Issue.record("\(command) should be a note")
                continue
            }
        }
        if case .result(let id) = TextPreview.make(for: .tool(.uuid), text: "x") { #expect(id.count == 36) } else { Issue.record("uuid shows an example") }
    }

    /// Edit, Undo, sub-wheels, Back and snippets have nothing of their own to show.
    @Test func nonToolsHaveNothingOfTheirOwn() {
        for command: TextCommand in [.edit, .undo, .open(.more), .back(nil), .snippetGroup("")] {
            #expect(TextPreview.make(for: command, text: "x") == .none, "\(command)")
        }
    }

    /// The pane always has text: the text now, or a tool's result (David, 2026-11-20).
    @Test func thePaneShowsTheTextNowOrTheResult() {
        let text = "b\na"
        let now = TextPreview.Pane(caption: "Now", note: nil, body: text, line: 0)
        // Nothing highlighted yet, Edit, More, a group, Back, Undo, a snippet: the text now.
        #expect(TextPreview.pane(for: nil, title: nil, text: text) == now)
        for command: TextCommand in [.edit, .undo, .open(.more), .back(nil), .snippetGroup("")] {
            #expect(TextPreview.pane(for: command, title: "x", text: text) == now, "\(command)")
        }
        // A tool: its result, named.
        #expect(TextPreview.pane(for: .tool(.sortAZ), title: "Sort A to Z", text: text)
                == TextPreview.Pane(caption: "After Sort A to Z", note: nil, body: "a\nb", line: 0))
        // A note goes with the text now, not instead of it.
        let count = TextPreview.pane(for: .tool(.count), title: "Count", text: text)
        #expect(count.caption == "Now")
        #expect(count.body == text)
        #expect(count.note?.hasPrefix("Count: ") == true)
        #expect(TextPreview.pane(for: .tool(.trim), title: "Trim", text: "hi").note == "Trim: Nothing to change.")
        // A long text scrolls to two lines above the first change.
        let long = (0..<20).map(String.init).joined(separator: "\n")
        #expect(TextPreview.pane(for: .tool(.reverseLines), title: "Reverse", text: long).line == 0)
        #expect(TextPreview.pane(for: .tool(.upperCase), title: "UPPER", text: "1\n2\n3\n4\nabc").line == 2)
    }

    @Test func scrollsToTheFirstChangedLine() {
        #expect(TextPreview.firstChangedLine(from: "a\nb\nc", to: "a\nB\nc") == 1)
        #expect(TextPreview.firstChangedLine(from: "a\nb", to: "a\nb\nc") == 2)
        #expect(TextPreview.firstChangedLine(from: "a", to: "b") == 0)
        #expect(TextPreview.firstChangedLine(from: "same", to: "same") == 0)
    }

    /// The pane shows its caption, note and text. Never put on screen here.
    @Test func thePaneShowsCaptionNoteAndText() {
        let pane = TextPreviewPanel()
        let wheel = NSRect(x: 100, y: 100, width: 300, height: 300)
        pane.show(TextPreview.Pane(caption: "After Trim", note: nil, body: "after", line: 0), beside: wheel, onScreen: false)
        #expect(pane.shownText == "after")
        #expect(pane.shownCaption == "After Trim")
        #expect(pane.shownNote == "")
        pane.show(TextPreview.Pane(caption: "Now", note: "Count: counts", body: "text", line: 0), beside: wheel, onScreen: false)
        #expect(pane.shownCaption == "Now")
        #expect(pane.shownNote == "Count: counts")
        #expect(pane.shownText == "text")
        #expect(pane.isShowing)
        pane.hide()
        #expect(!pane.isShowing)
    }

    /// Every text source previews alike: the check never looks at where the text came
    /// from, or at the wedge. A file wheel, a closed wheel, no text or the setting off: no pane.
    @Test func everySourcePreviewsAlike() {
        #expect(SelectedTextController.previewBlocker(enabled: true, text: "b\na", isTextWheel: true, wheelVisible: true) == nil)
        #expect(SelectedTextController.previewBlocker(enabled: false, text: "b\na", isTextWheel: true, wheelVisible: true) == "setting off")
        #expect(SelectedTextController.previewBlocker(enabled: true, text: nil, isTextWheel: true, wheelVisible: true) == "no text session")
        #expect(SelectedTextController.previewBlocker(enabled: true, text: "", isTextWheel: true, wheelVisible: true) == "empty text")
        #expect(SelectedTextController.previewBlocker(enabled: true, text: "x", isTextWheel: true, wheelVisible: false) == "wheel closed")
        #expect(SelectedTextController.previewBlocker(enabled: true, text: "x", isTextWheel: false, wheelVisible: true) == "not a text wheel")
    }
}
