import AppKit

/// Fits the text of the label and search bar above the wheel inside the
/// panel. The tool's name stays whole; the wheel's name, the search path
/// and the query are cut with an ellipsis first.
enum PillText {
    static let fontSize: CGFloat = 12
    /// The widest text the label holds: the panel, less a margin and the
    /// label's own padding.
    static let room: CGFloat = WheelGeometry.panelSide - 16 - 24
    /// The search bar also holds a magnifier, a caret (or the selection's
    /// padding) and the gaps between them.
    static let searchRoom: CGFloat = room - 16 - 4 - 3 * 5

    enum Cut { case head, middle, tail }

    static func width(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// `text` cut to fit `width`, an ellipsis where the cut is; empty if not
    /// even the ellipsis fits.
    static func shorten(_ text: String, toFit width: CGFloat, at cut: Cut) -> String {
        guard self.width(text) > width else { return text }
        let characters = Array(text)
        func kept(_ count: Int) -> String {
            switch cut {
            case .head: "…" + String(characters.suffix(count))
            case .tail: String(characters.prefix(count)) + "…"
            case .middle: String(characters.prefix((count + 1) / 2)) + "…" + String(characters.suffix(count / 2))
            }
        }
        guard self.width(kept(0)) <= width else { return "" }
        var (low, high) = (0, characters.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if self.width(kept(middle)) <= width { low = middle } else { high = middle - 1 }
        }
        return kept(low)
    }

    /// "Copied: the quick… · Remove Blank Lines": the wheel's name, cut in
    /// the middle so `label` stays whole.
    static func label(name: String?, _ label: String) -> String {
        guard let name else { return label }
        let full = "\(name) · \(label)"
        guard width(full) > room else { return full }
        let short = shorten(name, toFit: room - width(" · \(label)"), at: .middle)
        return short.isEmpty ? label : "\(short) · \(label)"
    }

    /// The search bar's query and "· Name · Lines › Order". The path is cut
    /// first, from its end, then the query from its start, since the end is
    /// what was just typed.
    static func search(query: String, result: String?) -> (query: String, result: String?) {
        guard let result else { return (shorten(query, toFit: searchRoom, at: .head), nil) }
        func fits(_ query: String, _ result: String) -> Bool { width(query) + width("· \(result)") <= searchRoom }
        guard !fits(query, result) else { return (query, result) }
        let parts = result.components(separatedBy: " · ")
        let name = parts[0]
        if parts.count > 1 {
            let path = parts.dropFirst().joined(separator: " · ")
            let short = shorten(path, toFit: searchRoom - width(query) - width("· \(name) · "), at: .tail)
            if !short.isEmpty, short != "…" { return (query, "\(name) · \(short)") }
        }
        let short = shorten(query, toFit: searchRoom - width("· \(name)"), at: .head)
        return (short.isEmpty ? "…" : short, name)
    }
}
