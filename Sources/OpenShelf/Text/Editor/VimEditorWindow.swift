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
    /// The text came with Windows line breaks, which go back on at the end.
    private var usesCRLF = false
    private var scroll: NSScrollView?
    /// Where the wrap choice is remembered between windows, like the window size.
    private let defaults: UserDefaults
    static let wrapKey = "EditWindowWrapsLines"
    /// Said in the status line until the next key ("wrap off").
    private var notice: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Long lines wrap (the default) or scroll sideways.
    var wraps: Bool { defaults.object(forKey: Self.wrapKey) as? Bool ?? true }

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
        // vim's lines end in "\n"; Swift reads "\r\n" as one character.
        // Text that breaks every line with "\r\n" gets it back at the end; mixed text comes back with "\n".
        let lf = text.replacingOccurrences(of: "\r\n", with: "\n")
        usesCRLF = text.contains("\r\n") && !text.replacingOccurrences(of: "\r\n", with: "").contains("\n")
        textView?.load(lf)
    }

    /// The window's panel, for tests.
    var editorPanel: EditorPanel? { panel }

    /// The window's text view, for tests.
    var panelTextView: VimTextView? { textView }

    /// The text as it stands, with the line breaks it came with.
    var text: String {
        let text = textView?.string ?? ""
        return usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
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
            }
        }
        textView.onChange = { [weak self] in
            self?.notice = nil
            self?.updateStatus()
        }

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
        applyWrap()
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
        notice = wraps ? "wrap on" : "wrap off"
        updateStatus()
    }

    private func applyWrap() {
        guard let textView, let container = textView.textContainer else { return }
        let wraps = self.wraps
        scroll?.hasHorizontalScroller = !wraps
        textView.isHorizontallyResizable = !wraps
        container.widthTracksTextView = wraps
        if wraps {
            textView.autoresizingMask = [.width]
            textView.setFrameSize(NSSize(width: scroll?.contentSize.width ?? textView.frame.width, height: textView.frame.height))
            container.containerSize = NSSize(width: textView.frame.width, height: .greatestFiniteMagnitude)
        } else {
            textView.autoresizingMask = []
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        textView.sizeToFit()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Whether long lines wrap in the text view itself, for tests.
    var textViewWraps: Bool { textView?.textContainer?.widthTracksTextView ?? true }

    private func updateStatus() {
        guard let engine = textView?.engine else { return }
        if engine.mode == .commandLine {
            statusLeft?.stringValue = engine.commandLine
        } else if let message = engine.message {
            statusLeft?.stringValue = "\(engine.modeName) · \(message)"
        } else {
            statusLeft?.stringValue = engine.modeName
        }
        if let register = engine.recording, engine.mode != .commandLine {
            statusLeft?.stringValue += " · recording @\(register)"
        }
        if let notice { statusLeft?.stringValue += " · \(notice)" }
        statusRight?.stringValue = "⌘↩ puts it \(destination) · ⌘W cancels"
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

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if event.keyCode == 36 || event.keyCode == 76 { onFinish(); return true }
            if event.charactersIgnoringModifiers == "w" { onCancel(); return true }
        }
        // ⌥⌘Z toggles wrapping: with ⌘ it never types, and it is no vim key.
        if flags == [.command, .option], event.keyCode == 6 {
            onToggleWrap()
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

    override func keyDown(with event: NSEvent) {
        let key = Self.vimKey(for: event)
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

    private func utf16Offset(of index: Int) -> Int {
        engine.text.prefix(index).reduce(0) { $0 + $1.utf16.count }
    }

    private func characterIndex(utf16 offset: Int) -> Int {
        let text = string
        let index = String.Index(utf16Offset: min(offset, text.utf16.count), in: text)
        return text.distance(from: text.startIndex, to: index)
    }

    // A block cursor outside insert mode, as in vim.
    private var blockWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)]).width
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard engine.mode != .insert else { return super.drawInsertionPoint(in: rect, color: color, turnedOn: flag) }
        var block = rect
        block.size.width = blockWidth
        if flag {
            color.withAlphaComponent(0.5).set()
            block.fill()
        } else {
            setNeedsDisplay(block, avoidAdditionalLayout: true)
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = invalidRect
        rect.size.width += blockWidth
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
