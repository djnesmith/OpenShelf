import AppKit

/// The Edit window: the selection in a plain text view with vim keys.
/// ⌘↩ (or :w, :wq, :x, ZZ) finishes; ⌘W (or :q!, ZQ) cancels. Esc only leaves
/// insert or visual mode. The text is held in memory only.
@MainActor
final class VimEditorWindow: NSObject, NSWindowDelegate {
    static let shared = VimEditorWindow()

    private var panel: EditorPanel?
    private var textView: VimTextView?
    private var statusLeft: NSTextField?
    private var statusRight: NSTextField?
    private var onFinish: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var destination = ""
    /// The line break the text came with, which goes back on at the end.
    private var lineBreak = "\n"
    private var scroll: NSScrollView?
    /// Where the wrap choice is remembered between windows, like the window size.
    private let defaults: UserDefaults
    static let wrapKey = "EditWindowWrapsLines"
    static let lineNumbersKey = "EditWindowLineNumbers"
    private var ruler: LineNumberRuler?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Long lines wrap (the default) or scroll sideways.
    var wraps: Bool { defaults.object(forKey: Self.wrapKey) as? Bool ?? true }

    /// Line numbers: relative by default (as vim's number with relativenumber); a choice is remembered.
    var lineNumbers: LineNumbers { (defaults.string(forKey: Self.lineNumbersKey)).flatMap(LineNumbers.init) ?? .relative }

    var isOpen: Bool { panel?.isVisible == true }

    /// Opens the window on `text`, centred on `point`'s screen. `destination`
    /// says where ⌘↩ puts the result ("back into Mail", "on the clipboard").
    /// Returns false, and brings the open edit forward, when one is already open.
    @discardableResult
    func open(_ text: String, title: String, destination: String, near point: NSPoint?, onFinish: @escaping (String) -> Void, onCancel: @escaping () -> Void) -> Bool {
        if isOpen, let panel {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            return false
        }
        let panel = self.panel ?? makePanel()
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.destination = destination
        panel.title = title
        load(text)
        if !panel.isVisible { place(panel, near: point) }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        return true
    }

    /// Puts `text` in the window, in normal mode at the start.
    func load(_ text: String) {
        let (lf, lineBreak) = Self.splitLines(text)
        self.lineBreak = lineBreak
        textView?.load(lf)
    }

    /// The window's panel, for tests.
    var editorPanel: EditorPanel? { panel }

    /// The window's text view, for tests.
    var panelTextView: VimTextView? { textView }

    /// The text as it stands, with the line breaks it came with.
    var text: String {
        let text = textView?.string ?? ""
        return lineBreak == "\n" ? text : text.replacingOccurrences(of: "\n", with: lineBreak)
    }

    /// The breaks the text view shows as new lines, besides "\n": Windows', old Mac's, and
    /// Unicode's (Notes, Mail and TextEdit use U+2028 for Shift-Return).
    static let otherLineBreaks = ["\r\n", "\r", "\u{2028}", "\u{2029}", "\u{0085}"]

    /// The text with every line break as vim's "\n", and the break to put back at the
    /// end: the one the text used, when it used only one kind; otherwise "\n".
    /// Without this, lines the window shows apart are one line to vim, and j does nothing.
    static func splitLines(_ text: String) -> (text: String, lineBreak: String) {
        // "\r\n" goes first: searching for "\n" or "\r" alone would find it too.
        var rest = text
        var used: [String] = []
        for lineBreak in otherLineBreaks + ["\n"] where rest.contains(lineBreak) {
            used.append(lineBreak)
            rest = rest.replacingOccurrences(of: lineBreak, with: "")
        }
        let lf = otherLineBreaks.reduce(text) { $0.replacingOccurrences(of: $1, with: "\n") }
        return (lf, used.count == 1 ? used[0] : "\n")
    }

    /// Builds the window once; later opens reuse it, so it opens at once.
    func makePanel() -> EditorPanel {
        let panel = EditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 320, height: 160)
        panel.setFrameAutosaveName("OpenShelf Edit Window")
        panel.delegate = self
        panel.onFinish = { [weak self] in self?.finish() }
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.onToggleWrap = { [weak self] in self?.setWrap(nil) }
        panel.onCycleLineNumbers = { [weak self] in
            guard let self else { return }
            self.setLineNumbers(self.lineNumbers.next)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let textView = VimTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 380))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        textView.onEffect = { [weak self] effect in
            switch effect {
            case .finish: self?.finish()
            case .cancel: self?.cancel()
            case .wrap(let on): self?.setWrap(on)
            case .number(let on):
                guard let self else { return }
                self.setLineNumbers(self.lineNumbers.settingNumber(on))
            case .relativeNumber(let on):
                guard let self else { return }
                self.setLineNumbers(self.lineNumbers.settingRelative(on))
            }
        }
        textView.onChange = { [weak self] in self?.updateStatus() }

        let left = NSTextField(labelWithString: "")
        let right = NSTextField(labelWithString: "")
        for label in [left, right] {
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }
        right.alignment = .right
        right.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [left, right])
        status.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 6, right: 10)

        let ruler = LineNumberRuler(textView: textView)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true

        let stack = NSStackView(views: [scroll, status])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        panel.contentView = content

        self.panel = panel
        self.textView = textView
        self.scroll = scroll
        self.ruler = ruler
        applyWrap()
        applyLineNumbers()
        statusLeft = left
        statusRight = right
        return panel
    }

    private func place(_ panel: NSPanel, near point: NSPoint?) {
        // A size the person chose is kept; the position is always near the wheel.
        let screen = NSScreen.screens.first { NSMouseInRect(point ?? NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        let centre = point ?? NSPoint(x: visible.midX, y: visible.midY)
        frame.origin.x = min(max(centre.x - frame.width / 2, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(centre.y - frame.height / 2, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }

    /// Turns wrapping on, off or (nil) the other way, remembers it, and says so.
    func setWrap(_ on: Bool?) {
        let wraps = on ?? !self.wraps
        defaults.set(wraps, forKey: Self.wrapKey)
        applyWrap()
        updateStatus()
    }

    /// Shows line numbers as `numbers`, remembers it, and says so.
    func setLineNumbers(_ numbers: LineNumbers) {
        defaults.set(numbers.rawValue, forKey: Self.lineNumbersKey)
        applyLineNumbers()
        updateStatus()
    }

    private func applyLineNumbers() {
        ruler?.numbers = lineNumbers
        scroll?.rulersVisible = lineNumbers != .off
        scroll?.tile()
        ruler?.refresh()
    }

    /// The gutter, for tests.
    var lineNumberRuler: LineNumberRuler? { ruler }

    private func applyWrap() {
        guard let textView, let container = textView.textContainer else { return }
        let wraps = self.wraps
        scroll?.hasHorizontalScroller = !wraps
        textView.isHorizontallyResizable = !wraps
        container.widthTracksTextView = wraps
        let visibleWidth = scroll?.contentSize.width ?? textView.frame.width
        if wraps {
            // Tracking the text view's width sets the container's, less the inset.
            textView.autoresizingMask = [.width]
            textView.minSize.width = 0
            textView.setFrameSize(NSSize(width: visibleWidth, height: textView.frame.height))
        } else {
            // At least as wide as the window, so clicks right of short lines still land.
            textView.autoresizingMask = []
            textView.minSize.width = visibleWidth
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        textView.sizeToFit()
        textView.scrollRangeToVisible(textView.selectedRange())
        ruler?.refresh()
    }

    /// The bottom line's keys, most needed first. The line-number key sits beside the wrap key.
    /// A command that did nothing (`failure`) is said right after the wrap key, until the next key.
    /// A nil `destination` leaves out where the text goes.
    static func hints(destination: String?, wraps: Bool, lineNumbers: LineNumbers? = nil, failure: String? = nil) -> String {
        let failed = failure.map { " · \($0)" } ?? ""
        let lines = lineNumbers.map { " · ⌥⌘L lines: \($0.rawValue)" } ?? ""
        let goes = destination.map { " · the text goes \($0)" } ?? ""
        return "⌘↩ done · ⌘W cancel · ⌥⌘Z wrap: \(wraps ? "on" : "off")\(failed)\(lines)\(goes)"
    }

    /// The hints that fit in `width`: a narrow window leaves out where the text goes first
    /// (David, 2026-11-19), then the line-number key; past that the end is cut.
    static func hints(destination: String, wraps: Bool, lineNumbers: LineNumbers, failure: String? = nil, fitting width: CGFloat) -> NSAttributedString {
        let tries = [
            hints(destination: destination, wraps: wraps, lineNumbers: lineNumbers, failure: failure),
            hints(destination: nil, wraps: wraps, lineNumbers: lineNumbers, failure: failure),
            hints(destination: nil, wraps: wraps, failure: failure),
        ]
        let styled = tries.map { styled($0, failure: failure) }
        return styled.first { $0.size().width <= width } ?? styled[styled.count - 1]
    }

    /// The bottom line's look (David, 2026-11-19: the keys were "hard to make out" and "too
    /// close together"): keys bright and in the system font, which draws ⌘ ⌥ ⇧ ↩ clearer than
    /// the monospaced one, with a little space between their glyphs; the words quieter; wide
    /// gaps between items; a failed command's reason in italics.
    static func styled(_ hints: String, failure: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: hints, attributes: [
            .font: statusFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ])
        let whole = hints as NSString
        for match in keyPattern.matches(in: hints, range: NSRange(location: 0, length: whole.length)) {
            text.addAttributes([.font: keyFont, .foregroundColor: NSColor.labelColor], range: match.range)
            // Space between a shortcut's glyphs, not after its last one.
            text.addAttribute(.kern, value: 2, range: NSRange(location: match.range.location, length: max(match.range.length - 1, 0)))
        }
        var search = NSRange(location: 0, length: whole.length)
        while case let found = whole.range(of: " · ", range: search), found.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: found.location + 1, length: 1))
            text.addAttribute(.kern, value: 5, range: NSRange(location: found.location, length: 2))
            search = NSRange(location: found.upperBound, length: whole.length - found.upperBound)
        }
        if let failure {
            let found = whole.range(of: failure)
            if found.location != NSNotFound {
                let italic = NSFontManager.shared.convert(statusFont, toHaveTrait: .italicFontMask)
                text.addAttribute(.font, value: italic, range: found)
            }
        }
        return text
    }

    /// A shortcut: modifier glyphs and the key after them.
    static let keyPattern = try! NSRegularExpression(pattern: "[⌃⌥⇧⌘]+[↩A-Za-z]?")
    static let statusFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let keyFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// The bottom line's right side, for tests.
    var bottomLineHints: String { statusRight?.stringValue ?? "" }

    /// Whether long lines wrap in the text view itself, for tests.
    var textViewWraps: Bool { textView?.textContainer?.widthTracksTextView ?? true }

    private func updateStatus() {
        guard let engine = textView?.engine else { return }
        if engine.mode == .commandLine {
            // The command line's own cursor: a blue bar after what is typed.
            statusLeft?.stringValue = engine.commandLine + "▏"
        } else if let message = engine.message {
            statusLeft?.stringValue = "\(engine.modeName) · \(message)"
        } else {
            statusLeft?.stringValue = engine.modeName
        }
        if let register = engine.recording, engine.mode != .commandLine {
            statusLeft?.stringValue += " · recording @\(register)"
        }
        // What the right side has: the window's width (the bar's, which may not be laid out
        // yet) less the left text, the gap and the edges.
        let room = (panel?.contentView?.bounds.width ?? 0) - (statusLeft?.fittingSize.width ?? 0) - 8 - 20
        statusRight?.attributedStringValue = Self.hints(destination: destination, wraps: wraps, lineNumbers: lineNumbers, failure: engine.failureHint, fitting: room)
        // Relative numbers follow the cursor.
        ruler?.refresh()
    }

    func windowDidResize(_ notification: Notification) {
        updateStatus()
    }

    private func finish() {
        guard textView != nil, let onFinish else { return }
        let result = text
        close()
        onFinish(result)
    }

    private func cancel() {
        let onCancel = onCancel
        close()
        onCancel?()
    }

    private func close() {
        onFinish = nil
        onCancel = nil
        textView?.load("")
        panel?.orderOut(nil)
    }

    /// The close button cancels, as ⌘W does.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}

/// The Edit window's panel: ⌘↩ finishes and ⌘W cancels in any mode.
final class EditorPanel: NSPanel {
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}
    var onToggleWrap: () -> Void = {}
    var onCycleLineNumbers: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if event.keyCode == 36 || event.keyCode == 76 { onFinish(); return true }
            if event.charactersIgnoringModifiers == "w" { onCancel(); return true }
        }
        // ⌥⌘Z toggles wrapping: with ⌘ it never types, and it is no vim key.
        if flags == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "z" {
            onToggleWrap()
            return true
        }
        // ⌥⌘L cycles line numbers, for the same reasons.
        if flags == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "l" {
            onCycleLineNumbers()
            return true
        }
        if flags == .command {
            // The app has no Edit menu, so the standard edit keys are sent here.
            let actions: [String: Selector] = ["c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:))]
            if let key = event.charactersIgnoringModifiers, let action = actions[key] {
                return NSApp.sendAction(action, to: nil, from: self)
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc belongs to vim; it never closes the window.
    override func cancelOperation(_ sender: Any?) {}
}

/// A text view that sends keys to a `VimEngine`, except in insert mode,
/// where it types as usual (input methods and dead keys included) until Esc.
final class VimTextView: NSTextView {
    private(set) var engine = VimEngine("")
    var onEffect: (VimEffect) -> Void = { _ in }
    var onChange: () -> Void = {}
    private var isRendering = false

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUp()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }

    private func setUp() {
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        insertionPointColor = Self.cursorBlue
        isRichText = false
        importsGraphics = false
        allowsUndo = false
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func load(_ text: String) {
        engine = VimEngine(text)
        // "+ and "* are the Mac clipboard.
        engine.usesSystemClipboard = true
        engine.clipboard = VimClipboard(
            read: { NSPasteboard.general.string(forType: .string) },
            write: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        )
        isRendering = true
        string = text
        isRendering = false
        render()
    }

    /// `jk` typed quickly leaves insert mode (ROADMAP C12), as Doom's evil-escape does.
    var insertEscape = InsertEscape()

    override func keyDown(with event: NSEvent) {
        let key = Self.vimKey(for: event)
        if engine.mode == .insert, !hasMarkedText(), event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let typed = event.characters, typed.count == 1, let character = typed.first,
           insertEscape.typed(character, at: event.timestamp) {
            // The first key of the pair went in as text: take it back, then leave insert mode.
            deleteBackward(nil)
            engine.syncInsert(text: string, cursor: characterIndex(utf16: selectedRange().location))
            let effect = engine.handle(.escape)
            render()
            if let effect { onEffect(effect) }
            return
        }
        if engine.mode == .insert {
            // Esc while an input method is composing belongs to the input method.
            guard !hasMarkedText(), key == .escape || key == .ctrl("[") || key == .ctrl("c") else {
                super.keyDown(with: event)
                return
            }
            engine.syncInsert(text: string, cursor: characterIndex(utf16: selectedRange().location))
        }
        guard let key else { return }
        let effect = engine.handle(key)
        render()
        if let effect { onEffect(effect) }
    }

    /// Clicks move vim's cursor too.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !isRendering, engine.mode == .insert { onChange() }
        guard !isRendering, !stillSelecting, engine.mode != .insert, let first = ranges.first?.rangeValue else { return }
        engine.click(at: characterIndex(utf16: first.location))
        render()
    }

    // Paste and undo go through vim in normal mode, and NSTextView's own
    // undo is off, so they can't get out of step.
    override func paste(_ sender: Any?) {
        if engine.mode == .insert { super.paste(sender) }
    }

    /// Outside insert mode only vim changes the text: not cut, drag and
    /// drop, or the text menu's transformations.
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        engine.mode == .insert && super.shouldChangeText(in: range, replacementString: replacementString)
    }

    private func render() {
        isRendering = true
        defer { isRendering = false }
        let text = engine.string
        if string != text { string = text }
        // A visual block shows as one selection per line (empty pieces left out).
        if let block = engine.blockSelection {
            let ranges = block.filter { !$0.isEmpty }.map { range -> NSValue in
                let start = utf16Offset(of: range.lowerBound)
                return NSValue(range: NSRange(location: start, length: utf16Offset(of: range.upperBound) - start))
            }
            let cursorRange = NSRange(location: utf16Offset(of: engine.cursor), length: 0)
            setSelectedRanges(ranges.isEmpty ? [NSValue(range: cursorRange)] : ranges, affinity: .downstream, stillSelecting: false)
            scrollRangeToVisible(cursorRange)
            needsDisplay = true
            onChange()
            return
        }
        let range: NSRange
        if let selection = engine.selection {
            let start = utf16Offset(of: selection.lowerBound)
            range = NSRange(location: start, length: utf16Offset(of: selection.upperBound) - start)
        } else {
            range = NSRange(location: utf16Offset(of: engine.cursor), length: 0)
        }
        setSelectedRange(range)
        scrollRangeToVisible(range)
        needsDisplay = true
        onChange()
    }

    /// vim's cursor as an offset in the view's text.
    var cursorUTF16Location: Int { utf16Offset(of: engine.cursor) }

    /// Typing in insert mode changes the text without vim; the window still follows it
    /// (the line numbers' width and the cursor's line).
    override func didChangeText() {
        super.didChangeText()
        if !isRendering { onChange() }
    }

    private func utf16Offset(of index: Int) -> Int {
        engine.text.prefix(index).reduce(0) { $0 + $1.utf16.count }
    }

    private func characterIndex(utf16 offset: Int) -> Int {
        let text = string
        let index = String.Index(utf16Offset: min(offset, text.utf16.count), in: text)
        return text.distance(from: text.startIndex, to: index)
    }

    // MARK: - Cursor

    /// The cursor's shape for each mode (David: "a block if normal and a | if
    /// insert ... blue for both ... see the letter in the blue block").
    enum CursorShape: Equatable { case block, bar, hidden }

    /// Whether the normal-mode block blinks (David's call; insert's bar always does).
    static let blockBlinks = true

    static func cursorShape(for mode: VimMode) -> CursorShape {
        switch mode {
        case .normal, .visual, .visualLine, .visualBlock, .replace: .block
        case .insert: .bar
        // Typing after ":" or "/": the bar is in the status line instead.
        case .commandLine: .hidden
        }
    }

    /// Doom One's blue, as in David's terminal theme.
    static let cursorBlue = NSColor(srgbRed: 0x51 / 255.0, green: 0xaf / 255.0, blue: 0xef / 255.0, alpha: 1)
    /// The letter inside the block: near-black reads on that blue in light and dark
    /// appearance alike (about 8:1; white would be about 2.4:1).
    static let cursorLetter = NSColor(srgbRed: 0x1c / 255.0, green: 0x1f / 255.0, blue: 0x24 / 255.0, alpha: 1)

    private var cellWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)]).width
    }

    /// The block covers the whole character under the cursor (an emoji or a
    /// letter with accents is one; a tab is its full width); at a line's end
    /// or on an empty line it is one cell wide.
    func blockRect(at index: Int, caret: NSRect) -> NSRect {
        var block = caret
        block.size.width = cellWidth
        guard let layoutManager, let textContainer, index < engine.text.count, engine.text[index] != "\n" else { return block }
        let start = engine.text.prefix(index).reduce(0) { $0 + $1.utf16.count }
        let characters = NSRange(location: start, length: engine.text[index].utf16.count)
        let glyphs = layoutManager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        if engine.text[index] == "\t", glyphs.upperBound < layoutManager.numberOfGlyphs {
            // A tab's glyph is narrow; the block runs to where the next character starts.
            rect.size.width = layoutManager.location(forGlyphAt: glyphs.upperBound).x - layoutManager.location(forGlyphAt: glyphs.location).x
        }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y = caret.origin.y
        rect.size.height = caret.height
        rect.size.width = max(rect.width, cellWidth)
        return rect
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        switch Self.cursorShape(for: engine.mode) {
        case .bar: super.drawInsertionPoint(in: rect, color: Self.cursorBlue, turnedOn: flag)
        case .hidden: return
        case .block:
            guard Self.blockBlinks else { return }
            let block = blockRect(at: engine.cursor, caret: rect)
            if flag { drawBlock(block, at: engine.cursor) } else { setNeedsDisplay(block, avoidAdditionalLayout: true) }
        }
    }

    /// The blue block, with the letter under it drawn again in near-black.
    private func drawBlock(_ block: NSRect, at index: Int) {
        Self.cursorBlue.set()
        block.fill()
        guard index < engine.text.count, !engine.text[index].isNewline, engine.text[index] != "\t" else { return }
        let letter = NSAttributedString(string: String(engine.text[index]), attributes: [
            .font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: Self.cursorLetter,
        ])
        let start = engine.text.prefix(index).reduce(0) { $0 + $1.utf16.count }
        guard let layoutManager else { return }
        let glyph = layoutManager.glyphIndexForCharacter(at: start)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = line.origin.y + textContainerOrigin.y + layoutManager.location(forGlyphAt: glyph).y
        let ascent = (font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)).ascender
        letter.draw(at: NSPoint(x: block.minX, y: baseline - ascent))
    }

    /// In visual mode the selection hides the caret, so the block at the
    /// selection's moving end is drawn here, without blinking; so is the
    /// normal-mode block when it doesn't blink.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let steady = engine.mode == .visual || engine.mode == .visualLine || (engine.mode == .normal && !Self.blockBlinks)
        guard steady, let layoutManager, layoutManager.numberOfGlyphs > 0 else { return }
        let offset = engine.text.prefix(engine.cursor).reduce(0) { $0 + $1.utf16.count }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(offset, layoutManager.numberOfGlyphs - 1))
        var caret = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        caret.origin.x = layoutManager.location(forGlyphAt: glyph).x + textContainerOrigin.x
        caret.origin.y += textContainerOrigin.y
        drawBlock(blockRect(at: engine.cursor, caret: caret), at: engine.cursor)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        // Wide enough for a block over an emoji or a tab.
        var rect = invalidRect
        rect.size.width += cellWidth * 8
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    static func vimKey(for event: NSEvent) -> VimKey? {
        switch event.keyCode {
        case 53: return .escape
        case 36, 76: return .enter
        case 51: return .backspace
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: break
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control), let c = event.charactersIgnoringModifiers?.lowercased().first { return .ctrl(c) }
        if flags.contains(.command) { return nil }
        return event.characters?.first.map(VimKey.char)
    }
}
