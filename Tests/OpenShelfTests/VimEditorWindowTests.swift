import AppKit
import Testing
@testable import OpenShelf

@MainActor
struct VimEditorWindowTests {
    static func key(_ characters: String, keyCode: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func keysMapToVimKeys() {
        #expect(VimTextView.vimKey(for: Self.key("\u{1b}", keyCode: 53)) == .escape)
        #expect(VimTextView.vimKey(for: Self.key("\r", keyCode: 36)) == .enter)
        #expect(VimTextView.vimKey(for: Self.key("\u{7f}", keyCode: 51)) == .backspace)
        #expect(VimTextView.vimKey(for: Self.key("", keyCode: 126)) == .up)
        #expect(VimTextView.vimKey(for: Self.key("G", keyCode: 5, modifiers: .shift)) == .char("G"))
        #expect(VimTextView.vimKey(for: Self.key("$", keyCode: 21, modifiers: .shift)) == .char("$"))
        #expect(VimTextView.vimKey(for: Self.key("r", keyCode: 15, modifiers: .control)) == .ctrl("r"))
        #expect(VimTextView.vimKey(for: Self.key("[", keyCode: 33, modifiers: .control)) == .ctrl("["))
        // ⌘ keys are the window's, not vim's.
        #expect(VimTextView.vimKey(for: Self.key("v", keyCode: 9, modifiers: .command)) == nil)
    }

    /// Keys typed into the window's text view edit the text through vim,
    /// and :wq finishes.
    @Test func theTextViewRunsVimKeys() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var effects: [VimEffect] = []
        view.onEffect = { effects.append($0) }
        view.load("one\ntwo\nthree")
        for c in "jdd" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.string == "one\nthree")
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
        for c in "vl" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.selectedRange() == NSRange(location: 4, length: 2))
        view.keyDown(with: Self.key("\u{1b}", keyCode: 53))
        for c in ":wq" { view.keyDown(with: Self.key(String(c))) }
        view.keyDown(with: Self.key("\r", keyCode: 36))
        #expect(effects == [.finish])
    }

    /// Windows line breaks are lines to vim, and go back on at the end.
    @Test func crlfTextIsEditedByLineAndKeepsItsBreaks() {
        let window = VimEditorWindow()
        _ = window.makePanel()
        window.load("one\r\ntwo\r\nthree")
        #expect(window.text == "one\r\ntwo\r\nthree")
        let view = window.panelTextView!
        for c in "jdd" { view.keyDown(with: Self.key(String(c))) }
        #expect(window.text == "one\r\nthree")
    }

    /// Mixed line breaks come back as "\n", rather than every line turning into "\r\n".
    @Test func mixedLineBreaksComeBackAsLF() {
        let window = VimEditorWindow()
        _ = window.makePanel()
        window.load("a\r\nb\nc")
        #expect(window.text == "a\nb\nc")
    }

    /// Outside insert mode, only vim changes the text (no cut, drop or transformations).
    @Test func onlyVimEditsOutsideInsertMode() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("abc")
        #expect(!view.shouldChangeText(in: NSRange(location: 0, length: 1), replacementString: ""))
        view.keyDown(with: Self.key("i"))
        #expect(view.shouldChangeText(in: NSRange(location: 0, length: 1), replacementString: ""))
    }

    /// Text past the BMP (emoji) keeps the view's selection in step with vim's cursor.
    @Test func cursorCountsCharactersNotUTF16() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("👋🏽a")
        view.keyDown(with: Self.key("l"))
        #expect(view.engine.cursor == 1)
        #expect(view.selectedRange().location == ("👋🏽" as NSString).length)
    }

    /// ⌘↩ finishes and ⌘W cancels; Esc does nothing to the window.
    @Test func panelKeys() {
        let panel = EditorPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        var calls: [String] = []
        panel.onFinish = { calls.append("finish") }
        panel.onCancel = { calls.append("cancel") }
        #expect(panel.performKeyEquivalent(with: Self.key("\r", keyCode: 36, modifiers: .command)))
        #expect(panel.performKeyEquivalent(with: Self.key("w", keyCode: 13, modifiers: .command)))
        panel.cancelOperation(nil)
        #expect(calls == ["finish", "cancel"])
    }

    /// Building the window and loading 2,000 lines into it, measured. The
    /// window is built once and reused, so later opens only load.
    @Test func opensFast() {
        let window = VimEditorWindow()
        let text = (1...2000).map { "line \($0) with some words in it" }.joined(separator: "\n")
        let clock = ContinuousClock()
        let build = clock.measure { _ = window.makePanel() }
        let load = clock.measure { window.load(text) }
        let reload = clock.measure { window.load("short") }
        print("Edit window: build \(build), load 2,000 lines \(load), load short \(reload)")
        #expect(window.text == "short")
        // Generous bounds, so a busy machine doesn't fail them; the printed times are the measure.
        #expect(build < .milliseconds(500))
        #expect(load < .milliseconds(250))
        #expect(reload < .milliseconds(50))
    }
}
