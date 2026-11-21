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
        // ⌘⇧R is smartparens' raise, s-R in David's Doom.
        #expect(VimTextView.vimKey(for: Self.key("R", keyCode: 15, modifiers: [.command, .shift])) == .command("R"))
        #expect(VimTextView.vimKey(for: Self.key("l", keyCode: 37, modifiers: .control)) == .ctrl("l"))
    }

    /// = runs the window's formatter (Re-indent's) on the whole text and takes back the lines'
    /// indentation; with no formatter for the text it says so and changes nothing.
    @Test @MainActor func reindentRunsTheFormatter() async {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var asked: [(String, String)] = []
        view.reindent = { text, ext in
            asked.append((text, ext))
            return "(defn f []\n  (g\n   x))"
        }
        view.load("(defn f []\n(g\nx))")
        for c in "j==" { view.keyDown(with: Self.key(String(c))) }
        for _ in 0..<100 where view.string == "(defn f []\n(g\nx))" { try? await Task.sleep(nanoseconds: 10_000_000) }
        #expect(view.string == "(defn f []\n  (g\nx))")
        #expect(asked.map(\.1) == ["clj"])
        view.load("just words")
        for c in "==" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.string == "just words")
        #expect(view.engine.message == "=: no formatter for this text")
    }

    /// Search matches get a background while / is typed and after the search, until :noh.
    @Test func searchMatchesAreHighlighted() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("ab é ab ab")
        func shown(_ at: Int) -> Bool {
            view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: at, effectiveRange: nil) != nil
        }
        for c in "/ab" { view.keyDown(with: Self.key(String(c))) }
        #expect(shown(0) && shown(5) && shown(8) && !shown(3))
        view.keyDown(with: Self.key("\r", keyCode: 36))
        #expect(shown(5))
        for c in ":noh" { view.keyDown(with: Self.key(String(c))) }
        view.keyDown(with: Self.key("\r", keyCode: 36))
        #expect(!shown(0) && !shown(5))
    }

    /// ⌘⇧R reaches vim through the panel, as ⌘ keys go to the window first.
    @Test @MainActor func raiseKeyReachesVim() {
        let panel = EditorPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        panel.contentView = view
        panel.makeFirstResponder(view)
        view.load("(a (b c) d)")
        for c in "fb" { view.keyDown(with: Self.key(String(c))) }
        #expect(panel.performKeyEquivalent(with: Self.key("R", keyCode: 15, modifiers: [.command, .shift])))
        #expect(view.string == "(a b d)")
    }

    /// Keys typed into the window's text view edit the text through vim,
    /// and :wq finishes.
    @Test func theTextViewRunsVimKeys() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var effects: [VimEffect] = []
        view.onEffect = { effects.append($0) }
        view.load("one\ntwo\nthree")
        // The window follows David's clipboard rule; a bare engine is plain vim.
        #expect(view.engine.usesSystemClipboard)
        #expect(!VimEngine("x").usesSystemClipboard)
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

    /// The range gx marked has a background until the second gx swaps it (evil-exchange).
    @Test func theExchangeMarkIsHighlighted() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("one two")
        func marked(_ at: Int) -> Bool {
            view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: at, effectiveRange: nil) != nil
        }
        for c in "gxiw" { view.keyDown(with: Self.key(String(c))) }
        #expect(marked(0) && marked(2) && !marked(4))
        for c in "wgxiw" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.string == "two one")
        #expect(!marked(0) && !marked(4))
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

    /// Lines broken by CR alone or U+2028/U+2029/U+0085 (Notes, Mail and TextEdit use U+2028 for
    /// Shift-Return) look like lines in the window, so they are lines to vim: j and d3j work, and
    /// the same break goes back on at the end.
    @Test(arguments: ["\r", "\u{2028}", "\u{2029}", "\u{0085}"])
    func otherLineBreaksAreLines(lineBreak: String) {
        let window = VimEditorWindow()
        _ = window.makePanel()
        window.load(["one", "two", "three", "four", "five"].joined(separator: lineBreak))
        let view = window.panelTextView!
        for c in "d3j" { view.keyDown(with: Self.key(String(c))) }
        #expect(window.text == "five")
        window.load(["one", "two", "three"].joined(separator: lineBreak))
        for c in "jdd" { view.keyDown(with: Self.key(String(c))) }
        #expect(window.text == "one" + lineBreak + "three")
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

    static func scratchDefaults() -> UserDefaults {
        let name = "OpenShelfTests.wrap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Wrapping is on by default; turning it off makes long lines scroll
    /// sideways, and the next window remembers the choice.
    @Test func wrapTogglesAndIsRemembered() {
        let defaults = Self.scratchDefaults()
        let window = VimEditorWindow(defaults: defaults)
        _ = window.makePanel()
        #expect(window.wraps)
        #expect(window.textViewWraps)
        window.setWrap(nil)
        #expect(!window.wraps)
        #expect(!window.textViewWraps)
        #expect(window.panelTextView?.isHorizontallyResizable == true)
        let next = VimEditorWindow(defaults: defaults)
        _ = next.makePanel()
        #expect(!next.textViewWraps)
        // Off, the text view is at least as wide as the window.
        let view = next.panelTextView!
        #expect(view.frame.width >= view.enclosingScrollView!.contentSize.width)
        next.setWrap(true)
        #expect(next.textViewWraps)
        // Back on, the text wraps inside the visible width, inset included.
        let container = view.textContainer!.containerSize.width
        #expect(container <= view.enclosingScrollView!.contentSize.width - 2 * view.textContainerInset.width + 0.5)
    }

    /// :set wrap, :set nowrap, :set wrap! and :set invwrap.
    @Test func setWrapOnTheCommandLine() {
        for (command, effect) in [("set wrap", VimEffect.wrap(true)), ("set nowrap", .wrap(false)), ("set wrap!", .wrap(nil)), ("set invwrap", .wrap(nil))] {
            var engine = VimEngine("a")
            #expect(engine.handle(VimEngineTests.keys(":\(command)<CR>")) == effect, "\(command)")
        }
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        _ = window.makePanel()
        window.load("abc")
        for c in ":set nowrap" { window.panelTextView?.keyDown(with: Self.key(String(c))) }
        window.panelTextView?.keyDown(with: Self.key("\r", keyCode: 36))
        #expect(!window.textViewWraps)
    }

    /// ⌥⌘Z never reaches vim: the text, the mode, a pending operator and a
    /// macro being recorded are as they were.
    @Test func theWrapHotkeyLeavesVimAlone() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        let panel = window.makePanel()
        window.load("one two")
        let view = window.panelTextView!
        for c in "qad" { view.keyDown(with: Self.key(String(c))) }
        #expect(panel.performKeyEquivalent(with: Self.key("z", keyCode: 6, modifiers: [.command, .option])))
        #expect(!window.textViewWraps)
        #expect(view.engine.recording == "a")
        #expect(view.engine.mode == .normal)
        for c in "wq" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.string == "two")
        #expect(view.engine.registers["a"]?.text == "dw")
    }

    /// A blue block in normal and visual mode, a bar in insert; while typing
    /// a ":" or "/" command the bar is in the status line instead.
    @Test func cursorShapeFollowsTheMode() {
        #expect(VimTextView.cursorShape(for: .normal) == .block)
        #expect(VimTextView.cursorShape(for: .visual) == .block)
        #expect(VimTextView.cursorShape(for: .visualLine) == .block)
        #expect(VimTextView.cursorShape(for: .insert) == .bar)
        #expect(VimTextView.cursorShape(for: .commandLine) == .hidden)
        #expect(VimTextView.cursorBlue.usingColorSpace(.sRGB)!.blueComponent > 0.9)
    }

    /// The block covers the whole character: one cell for a letter, wider for
    /// an emoji or a tab, one cell at a line's end or past the text.
    @Test func blockCoversTheWholeCharacter() {
        let view = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load("a😀\tb\n")
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let caret = NSRect(x: 0, y: 0, width: 1, height: 16)
        let cell = view.blockRect(at: 0, caret: caret).width
        #expect(cell > 4)
        #expect(view.blockRect(at: 1, caret: caret).width > cell)
        #expect(view.blockRect(at: 2, caret: caret).width >= cell)
        #expect(view.blockRect(at: 4, caret: caret).width == cell)
        #expect(view.blockRect(at: 99, caret: caret).width == cell)
        // Asking for the block changes neither the text nor vim.
        #expect(view.string == "a😀\tb\n")
        #expect(view.engine.mode == .normal)
        #expect(view.engine.cursor == 0)
    }

    /// Line numbers are relative by default; a stored choice wins, and the gutter shows unless off.
    @Test func lineNumbersAreRelativeByDefaultAndRemembered() {
        let defaults = Self.scratchDefaults()
        let window = VimEditorWindow(defaults: defaults)
        _ = window.makePanel()
        #expect(window.lineNumbers == .relative)
        #expect(window.panelTextView?.enclosingScrollView?.rulersVisible == true)
        window.setLineNumbers(.off)
        #expect(window.panelTextView?.enclosingScrollView?.rulersVisible == false)
        let next = VimEditorWindow(defaults: defaults)
        _ = next.makePanel()
        #expect(next.lineNumbers == .off)
        #expect(next.panelTextView?.enclosingScrollView?.rulersVisible == false)
    }

    /// ⌥⌘L cycles on, relative, off, on (so from the relative default: off, on, relative),
    /// and never reaches vim: the text, a pending operator and a recording are as they were.
    @Test func theLineNumberHotkeyCyclesAndLeavesVimAlone() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        let panel = window.makePanel()
        window.load("one two")
        let view = window.panelTextView!
        for c in "qad" { view.keyDown(with: Self.key(String(c))) }
        var seen: [LineNumbers] = []
        for _ in 0..<3 {
            #expect(panel.performKeyEquivalent(with: Self.key("l", keyCode: 37, modifiers: [.command, .option])))
            seen.append(window.lineNumbers)
        }
        #expect(seen == [.off, .on, .relative])
        #expect(view.engine.recording == "a")
        for c in "wq" { view.keyDown(with: Self.key(String(c))) }
        #expect(view.string == "two")
        #expect(view.engine.registers["a"]?.text == "dw")
    }

    /// :set number, nonumber, number!, relativenumber and their short and inv forms.
    @Test func setNumberOnTheCommandLine() {
        let effects: [(String, VimEffect)] = [
            ("set number", .number(true)), ("set nu", .number(true)), ("set nonumber", .number(false)), ("set nonu", .number(false)),
            ("set nu!", .number(nil)), ("set number!", .number(nil)), ("set invnumber", .number(nil)), ("set invnu", .number(nil)),
            ("set relativenumber", .relativeNumber(true)), ("set rnu", .relativeNumber(true)),
            ("set norelativenumber", .relativeNumber(false)), ("set nornu", .relativeNumber(false)),
            ("set rnu!", .relativeNumber(nil)), ("set invrnu", .relativeNumber(nil)), ("set invrelativenumber", .relativeNumber(nil)),
        ]
        for (command, effect) in effects {
            var engine = VimEngine("a")
            #expect(engine.handle(VimEngineTests.keys(":\(command)<CR>")) == effect, "\(command)")
        }
        // From each state: number on, off, toggled; relative on, off, toggled.
        #expect(LineNumbers.allCases.map { $0.settingNumber(true) } == [.on, .relative, .on])
        #expect(LineNumbers.allCases.map { $0.settingNumber(false) } == [.off, .off, .off])
        #expect(LineNumbers.allCases.map { $0.settingNumber(nil) } == [.off, .off, .on])
        #expect(LineNumbers.allCases.map { $0.settingRelative(true) } == [.relative, .relative, .relative])
        #expect(LineNumbers.allCases.map { $0.settingRelative(false) } == [.on, .on, .off])
        #expect(LineNumbers.allCases.map { $0.settingRelative(nil) } == [.relative, .on, .relative])
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        _ = window.makePanel()
        window.load("abc")
        for c in ":set nornu" { window.panelTextView?.keyDown(with: Self.key(String(c))) }
        window.panelTextView?.keyDown(with: Self.key("\r", keyCode: 36))
        #expect(window.lineNumbers == .on)
    }

    /// One number per real line, none on a wrapped line's further rows; relative numbers
    /// count from the cursor's line, which shows its own; the numbers are not in the text.
    @Test func theGutterNumbersRealLines() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        let panel = window.makePanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        let long = String(repeating: "word ", count: 60)
        window.load("one\n\(long)\nthree\nfour\n")
        let view = window.panelTextView!
        let ruler = window.lineNumberRuler!
        let everything = NSRect(x: 0, y: 0, width: 10_000, height: 10_000)
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        for c in "jj" { view.keyDown(with: Self.key(String(c))) }
        let wrapped = ruler.labels(in: everything)
        // Five real lines, the last the empty one after the final line break.
        #expect(wrapped.map(\.text) == ["2", "1", "3", "1", "2"])
        #expect(wrapped.map(\.isCurrent) == [false, false, true, false, false])
        let row = wrapped[0].height
        #expect(wrapped[2].top - wrapped[1].top > row * 1.5)
        #expect(wrapped == wrapped.sorted { $0.top < $1.top })
        window.setWrap(false)
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let unwrapped = ruler.labels(in: everything)
        #expect(abs((unwrapped[2].top - unwrapped[1].top) - row) < 0.5)
        window.setLineNumbers(.on)
        #expect(ruler.labels(in: everything).map(\.text) == ["1", "2", "3", "4", "5"])
        window.setLineNumbers(.off)
        #expect(ruler.labels(in: everything).isEmpty)
        #expect(window.text == "one\n\(long)\nthree\nfour\n")
        // Without a final line break there is no empty last line to number; an empty text has one line.
        window.setLineNumbers(.on)
        window.load("one\ntwo")
        #expect(ruler.labels(in: everything).map(\.text) == ["1", "2"])
        window.load("")
        #expect(ruler.labels(in: everything).map(\.text) == ["1"])
    }

    /// Typing in insert mode keeps the gutter up to date: it widens for a new digit and
    /// counts from the caret's line. In visual mode it counts from the selection's moving
    /// end, as vim does. A pasted U+2028 is not a line to vim, so it gets no number.
    @Test func theGutterFollowsInsertAndVisualMode() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        let panel = window.makePanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        let view = window.panelTextView!
        let ruler = window.lineNumberRuler!
        let everything = NSRect(x: 0, y: 0, width: 10_000, height: 100_000)
        window.load((1...99).map(String.init).joined(separator: "\n"))
        let narrow = ruler.ruleThickness
        for c in "GA" { view.keyDown(with: Self.key(String(c))) }
        view.insertText("\nx", replacementRange: view.selectedRange())
        #expect(ruler.ruleThickness == ruler.thickness(lines: 100))
        #expect(ruler.ruleThickness > narrow)
        #expect(ruler.labels(in: everything).last == ruler.labels(in: everything).first { $0.isCurrent })
        #expect(ruler.labels(in: everything).last?.text == "100")

        window.load("a\nb\nc\nd\ne")
        for c in "vjj" { view.keyDown(with: Self.key(String(c))) }
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        #expect(ruler.labels(in: everything).map(\.text) == ["2", "1", "3", "1", "2"])

        view.keyDown(with: Self.key("\u{1b}", keyCode: 53))
        window.load("a\nb")
        for c in "A" { view.keyDown(with: Self.key(String(c))) }
        view.insertText("1\u{2028}2", replacementRange: view.selectedRange())
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        #expect(ruler.labels(in: everything).count == 2)
    }

    /// A failed command shows its reason after the wrap key, in the bottom line's gray, until the next key.
    @Test func theBottomLineSaysWhyACommandDidNothing() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        let panel = window.makePanel()
        panel.setContentSize(NSSize(width: 1200, height: 300))
        window.load("a\nb")
        let view = window.panelTextView!
        for c in "jd3j" { view.keyDown(with: Self.key(String(c))) }
        #expect(window.text == "a\nb")
        #expect(window.bottomLineHints.contains("⌥⌘Z wrap: on · d3j: no line below · ⌥⌘L lines: relative"))
        view.keyDown(with: Self.key("k"))
        #expect(!window.bottomLineHints.contains("no line below"))
    }

    /// The gutter is as wide as the largest line number needs.
    @Test func theGutterFitsTheLineCount() {
        let window = VimEditorWindow(defaults: Self.scratchDefaults())
        _ = window.makePanel()
        let ruler = window.lineNumberRuler!
        window.load("a\nb")
        let two = ruler.ruleThickness
        window.load((1...1200).map(String.init).joined(separator: "\n"))
        window.panelTextView?.keyDown(with: Self.key("j"))
        #expect(ruler.ruleThickness > two)
        #expect(ruler.ruleThickness == ruler.thickness(lines: 1200))
    }

    /// The bottom line shows the line-number key and state beside the wrap key. A narrow
    /// window leaves out where the text goes first, then the line-number key.
    @Test func bottomLineShowsTheLineNumberKey() {
        func fit(_ width: CGFloat) -> String {
            VimEditorWindow.hints(destination: "back into Mail", wraps: true, lineNumbers: .relative, fitting: width).string
        }
        #expect(fit(2000) == "⌘↩ done · ⌘W cancel · ⌥⌘Z wrap: on · ⌥⌘L lines: relative · the text goes back into Mail")
        let full = VimEditorWindow.hints(destination: "back into Mail", wraps: true, lineNumbers: .relative, fitting: 2000).size().width
        let noDestination = VimEditorWindow.styled(VimEditorWindow.hints(destination: nil, wraps: true, lineNumbers: .relative), failure: nil).size().width
        #expect(fit((full + noDestination) / 2) == "⌘↩ done · ⌘W cancel · ⌥⌘Z wrap: on · ⌥⌘L lines: relative")
        #expect(fit(200) == "⌘↩ done · ⌘W cancel · ⌥⌘Z wrap: on")
        #expect(VimEditorWindow.hints(destination: "x", wraps: false, lineNumbers: .off).contains("⌥⌘L lines: off"))
    }

    /// The keys are brighter than the words, in a bolder font, with space between a
    /// shortcut's glyphs; a failed command's reason is in italics.
    @Test func bottomLineKeysStandOut() {
        let text = VimEditorWindow.styled(VimEditorWindow.hints(destination: "x", wraps: true, failure: "d3j: no line below"), failure: "d3j: no line below")
        let string = text.string as NSString
        func attributes(of piece: String) -> [NSAttributedString.Key: Any] {
            text.attributes(at: string.range(of: piece).location, effectiveRange: nil)
        }
        #expect(attributes(of: "⌥⌘Z")[.foregroundColor] as? NSColor == .labelColor)
        #expect(attributes(of: "⌥⌘Z")[.font] as? NSFont == VimEditorWindow.keyFont)
        #expect((attributes(of: "⌥⌘Z")[.kern] as? CGFloat ?? 0) > 0)
        #expect(attributes(of: "wrap")[.foregroundColor] as? NSColor == .secondaryLabelColor)
        #expect(attributes(of: "d3j: no")[.font] as? NSFont != VimEditorWindow.statusFont)
        #expect(NSFontManager.shared.traits(of: attributes(of: "d3j: no")[.font] as! NSFont).contains(.italicFontMask))
    }

    /// The bottom line always shows the wrap key and its state, after the keys
    /// needed most, so a narrow window cuts the least needed part first.
    @Test func bottomLineShowsTheWrapKeyAndState() {
        let on = VimEditorWindow.hints(destination: "back into Mail", wraps: true)
        #expect(on == "⌘↩ done · ⌘W cancel · ⌥⌘Z wrap: on · the text goes back into Mail")
        #expect(VimEditorWindow.hints(destination: "on the clipboard", wraps: false).contains("⌥⌘Z wrap: off"))
        #expect(on.range(of: "⌘W")!.lowerBound < on.range(of: "⌥⌘Z")!.lowerBound)
    }
}
