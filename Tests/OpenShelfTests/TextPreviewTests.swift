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
        for command: TextCommand in [.tool(.count), .tool(.sha256), .tool(.jwt), .tool(.reindent), .tool(.toMarkdown), .tool(.markdownLink), .edit, .undo, .convert(.json)] {
            guard case .note = TextPreview.make(for: command, text: "x") else {
                Issue.record("\(command) should be a note")
                continue
            }
        }
        if case .result(let id) = TextPreview.make(for: .tool(.uuid), text: "x") { #expect(id.count == 36) } else { Issue.record("uuid shows an example") }
    }

    @Test func subWheelsAndSnippetsShowNothing() {
        #expect(TextPreview.make(for: .open(.more), text: "x") == .none)
        #expect(TextPreview.make(for: .back(nil), text: "x") == .none)
        #expect(TextPreview.make(for: .snippetGroup(""), text: "x") == .none)
    }

    @Test func scrollsToTheFirstChangedLine() {
        #expect(TextPreview.firstChangedLine(from: "a\nb\nc", to: "a\nB\nc") == 1)
        #expect(TextPreview.firstChangedLine(from: "a\nb", to: "a\nb\nc") == 2)
        #expect(TextPreview.firstChangedLine(from: "a", to: "b") == 0)
        #expect(TextPreview.firstChangedLine(from: "same", to: "same") == 0)
    }

    /// The pane shows the result or the note; nothing hides it. Never put on screen here.
    @Test func thePaneShowsResultsAndNotes() {
        let pane = TextPreviewPanel()
        let wheel = NSRect(x: 100, y: 100, width: 300, height: 300)
        pane.show(.result("after"), title: "Trim", beside: wheel, onScreen: false)
        #expect(pane.shownText == "after")
        #expect(pane.shownCaption == "After Trim")
        pane.show(.note("Counts…"), title: "Count", beside: wheel, onScreen: false)
        #expect(pane.shownCaption == "Count")
        #expect(pane.shownText == "Counts…")
        #expect(pane.isShowing)
        pane.show(.none, title: "More", beside: wheel, onScreen: false)
        #expect(!pane.isShowing)
        #expect(TextPreviewPanel.isEnabled || UserDefaults.standard.object(forKey: TextPreviewPanel.enabledKey) != nil)
    }
}
