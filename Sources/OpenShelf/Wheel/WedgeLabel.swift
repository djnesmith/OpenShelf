import AppKit

/// How a wedge sets its name: bold capitals, wrapped at spaces onto up to
/// two lines, at the largest size from `baseSize` down to `minimumScale` of
/// it that fits the wedge. The view and the tests both use this, so a test
/// can say which names don't fit.
enum WedgeLabel {
    static let tracking: CGFloat = 0.4
    static let lineLimit = 2
    /// 7.1 pt for a 9.5 pt label.
    static let minimumScale: CGFloat = 0.75
    /// A second line sits nearer the hub, where the wedge is narrower.
    static let secondLineInset: CGFloat = 8

    /// Format names stand alone, so they get a larger label.
    static func baseSize(for item: WheelItem) -> CGFloat {
        item.systemImage != nil ? 9.5 : item.appIconPath != nil ? 11 : 13
    }

    /// The size to draw `title` at in a label `width` wide, or nil if it
    /// doesn't fit even at the smallest size.
    static func fontSize(for title: String, base: CGFloat, width: CGFloat) -> CGFloat? {
        let steps = 10
        for step in 0...steps {
            let scale = 1 - (1 - minimumScale) * CGFloat(step) / CGFloat(steps)
            let size = base * scale
            guard let lines = lines(title, size: size, width: width), lines.count <= lineLimit else { continue }
            if lines.dropFirst().allSatisfy({ self.width(of: $0, size: size) <= width - secondLineInset }) { return size }
        }
        return nil
    }

    /// What the wedge shows: capitals, with a sub-wheel's ▸ kept on the
    /// line of the word before it.
    static func text(_ title: String) -> String {
        title.uppercased().replacingOccurrences(of: " ▸", with: "\u{00A0}▸")
    }

    /// `title` as shown, wrapped at spaces to `width`, or nil if one word is
    /// wider than that on its own.
    static func lines(_ title: String, size: CGFloat, width: CGFloat) -> [String]? {
        var lines: [String] = []
        for word in text(title).split(separator: " ").map(String.init) {
            guard self.width(of: word, size: size) <= width else { return nil }
            if let last = lines.last, self.width(of: last + " " + word, size: size) <= width {
                lines[lines.count - 1] = last + " " + word
            } else {
                lines.append(word)
            }
        }
        return lines
    }

    static func width(of text: String, size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking])
        return ceil(attributed.size().width)
    }
}
