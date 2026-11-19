import AppKit

/// How the Edit window numbers its lines (David: on by default, relative, gray).
enum LineNumbers: String, CaseIterable, Sendable {
    /// Every line's own number.
    case on
    /// The cursor's line its own number, the others their distance from it,
    /// as vim's number with relativenumber.
    case relative
    case off

    /// ⌥⌘L's order: on, relative, off, on.
    var next: LineNumbers {
        switch self {
        case .on: .relative
        case .relative: .off
        case .off: .on
        }
    }

    /// After `:set number` (true), `nonumber` (false) or `number!` (nil). With
    /// relativenumber still set, vim's nonumber would number from 0; this window
    /// turns the numbers off instead.
    func settingNumber(_ on: Bool?) -> LineNumbers {
        switch on {
        case true?: self == .off ? .on : self
        case false?: .off
        case nil: self == .off ? .on : .off
        }
    }

    /// After `:set relativenumber`, `norelativenumber` or `relativenumber!`.
    func settingRelative(_ on: Bool?) -> LineNumbers {
        switch on {
        case true?: .relative
        case false?: self == .relative ? .on : self
        case nil: self == .relative ? .on : .relative
        }
    }
}

/// The Edit window's gutter: one number per real line, left of the text, in
/// the text's font and a muted gray. A wrapped line's further rows have none.
/// It is a ruler beside the text, so the numbers scroll with the text and are
/// never selected or part of it.
final class LineNumberRuler: NSRulerView {
    var numbers: LineNumbers = .relative
    private weak var textView: NSTextView?
    /// Space either side of the numbers.
    static let padding: CGFloat = 6

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
        // Views draw past their bounds unless told not to; the gutter's background would cover the text.
        clipsToBounds = true
        ruleThickness = thickness(lines: 1)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// Gray that reads in light and dark, dimmer than the text; the cursor's line a touch brighter.
    static let color = NSColor.tertiaryLabelColor
    static let currentColor = NSColor.secondaryLabelColor

    private var font: NSFont { textView?.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular) }

    /// Wide enough for the largest line number.
    func thickness(lines: Int) -> CGFloat {
        let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
        return ceil(CGFloat(max(String(lines).count, 2)) * digit + 2 * Self.padding)
    }

    /// Redraws, and widens or narrows to the line count. Runs on every key, so it counts
    /// on the text view's own string, and not at all with the numbers off.
    func refresh() {
        needsDisplay = true
        guard numbers != .off, let textView else { return }
        let text = textView.string as NSString
        let wanted = thickness(lines: Self.lineBreaks(in: text, before: text.length) + 1)
        if abs(ruleThickness - wanted) > 0.5 { ruleThickness = wanted }
    }

    /// How many "\n" come before `location`: vim's line index. Only "\n" counts, as in the
    /// engine; NSString's own line ranges would also split at U+2028 and the like.
    static func lineBreaks(in text: NSString, before location: Int) -> Int {
        var count = 0
        var position = 0
        while position < location {
            let found = text.range(of: "\n", options: .literal, range: NSRange(location: position, length: location - position))
            guard found.location != NSNotFound else { break }
            count += 1
            position = found.upperBound
        }
        return count
    }

    /// The cursor, where relative numbers count from: vim's cursor (the moving end of a
    /// visual selection), or the caret while typing.
    private var cursorLocation: Int {
        guard let textView else { return 0 }
        if let vim = textView as? VimTextView, vim.engine.mode != .insert { return vim.cursorUTF16Location }
        return textView.selectedRange().location
    }

    /// One label: the text shown, where its line's first row is (in the text
    /// view's coordinates), and whether it is the cursor's line.
    struct Label: Equatable {
        var text: String
        var top: CGFloat
        var height: CGFloat
        var isCurrent: Bool
    }

    /// The labels for the lines whose first row is in `rect` (text view coordinates).
    func labels(in rect: NSRect) -> [Label] {
        guard numbers != .off, let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return [] }
        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let glyphs = layout.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let first = min(layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).location, text.length)
        let current = Self.lineBreaks(in: text, before: min(cursorLocation, text.length))
        // The start of the line the first visible row belongs to.
        let before = text.range(of: "\n", options: [.literal, .backwards], range: NSRange(location: 0, length: first))
        var start = before.location == NSNotFound ? 0 : before.upperBound
        var line = Self.lineBreaks(in: text, before: start)
        var labels: [Label] = []
        while start <= text.length {
            let row: NSRect
            if start == text.length {
                // The empty last line after a final line break, or an empty text.
                guard start == 0 || text.character(at: start - 1) == 10 else { break }
                row = layout.extraLineFragmentRect
            } else {
                row = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: start), effectiveRange: nil)
            }
            let top = row.minY + origin.y
            if top > rect.maxY { break }
            let shown = numbers == .relative && line != current ? abs(line - current) : line + 1
            labels.append(Label(text: String(shown), top: top, height: row.height, isCurrent: line == current))
            guard start < text.length else { break }
            let found = text.range(of: "\n", options: .literal, range: NSRange(location: start, length: text.length - start))
            guard found.location != NSNotFound else { break }
            start = found.upperBound
            line += 1
        }
        return labels
    }

    override func draw(_ dirtyRect: NSRect) {
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        bounds.intersection(dirtyRect).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        for label in labels(in: textView.visibleRect) {
            let top = convert(NSPoint(x: 0, y: label.top), from: textView).y
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: label.isCurrent ? Self.currentColor : Self.color,
                .paragraphStyle: style,
            ]
            (label.text as NSString).draw(in: NSRect(x: 0, y: top, width: ruleThickness - Self.padding, height: label.height), withAttributes: attributes)
        }
    }

    /// Clicks in the gutter do nothing (rulers otherwise add markers).
    override func mouseDown(with event: NSEvent) {}
}
