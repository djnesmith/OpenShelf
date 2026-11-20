import Foundation

/// The text tools used last, newest first, kept between launches (ROADMAP C7 "recent
/// first"): the three newest take the first wheel's free slots.
enum TextRecents {
    static let key = "TextWheelRecentTools"
    static let shown = 3
    static let kept = 20

    static func load(_ defaults: UserDefaults = .standard) -> [TextTool] {
        TextTool.decode(defaults.stringArray(forKey: key) ?? [])
    }

    static func record(_ tool: TextTool, _ defaults: UserDefaults = .standard) {
        let list = [tool] + load(defaults).filter { $0 != tool }
        defaults.set(list.prefix(kept).map(\.storedName), forKey: key)
    }
}

/// The tools David chooses for the first text wheel (ROADMAP C7 "favourites"), in place
/// of Trim and Clean Up. Up to four.
enum TextFavorites {
    static let key = "TextWheelFavorites"
    static let limit = 4

    static func load(_ defaults: UserDefaults = .standard) -> [TextTool] {
        Array(TextTool.decode(defaults.stringArray(forKey: key) ?? []).prefix(limit))
    }

    static func save(_ tools: [TextTool], _ defaults: UserDefaults = .standard) {
        defaults.set(tools.prefix(limit).map(\.storedName), forKey: key)
    }
}

extension TextTool {
    /// The case's name, stable across launches.
    var storedName: String { String(describing: self) }

    static func decode(_ names: [String]) -> [TextTool] {
        names.compactMap { name in allCases.first { $0.storedName == name } }
    }

    /// A tool that belongs on a wheel as a wedge: anything that works on any text
    /// (Re-indent and To Markdown appear by themselves when they apply).
    var isOnWheel: Bool { ![.reindent, .toMarkdown].contains(self) }
}
