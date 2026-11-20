import AppKit

/// The read-only pane to the right of the text wheel that shows a tool's result before
/// it runs (ROADMAP C13). It never takes focus and is never part of the text.
@MainActor
final class TextPreviewPanel {
    static let shared = TextPreviewPanel()
    static let enabledKey = "TextWheelPreview"
    static let size = NSSize(width: 380, height: 300)

    private var panel: NSPanel?
    private let textView = NSTextView()
    private let caption = NSTextField(labelWithString: "")

    var isVisible: Bool { panel?.isVisible == true }
    /// Whether a preview is up (on screen, or would be in a test that keeps it off).
    private(set) var isShowing = false
    /// The text shown, for tests.
    var shownText: String { textView.string }
    var shownCaption: String { caption.stringValue }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Shows `preview` beside `wheelFrame`, scrolled to `line`.
    func show(_ preview: TextPreview, title: String, beside wheelFrame: NSRect, line: Int = 0, onScreen: Bool = true) {
        guard preview != .none else { return hide() }
        let panel = self.panel ?? make()
        switch preview {
        case .result(let text):
            caption.stringValue = "After \(title)"
            textView.string = text
            textView.textColor = .labelColor
        case .note(let note):
            caption.stringValue = title
            textView.string = note
            textView.textColor = .secondaryLabelColor
        case .none:
            break
        }
        scroll(to: line)
        let screen = NSScreen.screens.first { $0.frame.intersects(wheelFrame) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: wheelFrame.maxX + 8, y: wheelFrame.midY - Self.size.height / 2)
        // No room on the right: the left side instead.
        if origin.x + Self.size.width > screen.maxX { origin.x = wheelFrame.minX - 8 - Self.size.width }
        origin.y = min(max(origin.y, screen.minY), screen.maxY - Self.size.height)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
        isShowing = true
        if onScreen { panel.orderFrontRegardless() }
    }

    func hide() {
        isShowing = false
        panel?.orderOut(nil)
    }

    /// The pane's content view, for tests.
    var contentView: NSView? { panel?.contentView }

    private func scroll(to line: Int) {
        guard line > 0, let layout = textView.layoutManager, let container = textView.textContainer else {
            textView.scrollToBeginningOfDocument(nil)
            return
        }
        let text = textView.string as NSString
        var location = 0
        for _ in 0..<line {
            let found = text.range(of: "\n", options: .literal, range: NSRange(location: location, length: text.length - location))
            guard found.location != NSNotFound else { break }
            location = found.upperBound
        }
        layout.ensureLayout(for: container)
        // A couple of lines above the change stay in view.
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        let stack = NSStackView(views: [caption, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
        panel.contentView = background
        self.panel = panel
        return panel
    }
}
