import Foundation

/// gq's re-wrapping (ROADMAP C12 item 4), as vim does it with its defaults. Pure.
enum VimFormat {
    /// `lines` re-wrapped to `width`: each paragraph (lines between blank ones) joined as J
    /// joins (one space, the next line's indentation dropped, spaces inside a line kept),
    /// then broken before the word that would pass `width`, new lines taking the first
    /// line's indentation. Blank lines stay as they are.
    static func wrap(_ lines: [String], width: Int) -> [String] {
        var out: [String] = []
        var paragraph: [String] = []
        func flush() {
            guard let first = paragraph.first else { return }
            let indent = String(first.prefix { $0 == " " || $0 == "\t" })
            var joined = first
            for line in paragraph.dropFirst() {
                let rest = line.drop { $0 == " " || $0 == "\t" }
                guard !rest.isEmpty else { continue }
                while joined.last == " " || joined.last == "\t" { joined.removeLast() }
                joined += " " + rest
            }
            out += breakLine(joined, indent: indent, width: width)
            paragraph = []
        }
        for line in lines {
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
                flush()
                out.append(line)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return out
    }

    /// `line` broken at spaces so each piece is at most `width` long where it can be; a
    /// word longer than that stays whole on its own line.
    static func breakLine(_ line: String, indent: String, width: Int) -> [String] {
        var pieces: [String] = []
        var rest = Array(line)
        while rest.count > width {
            // The last space within the width, after the indentation.
            let limit = min(width, rest.count - 1)
            var cut = (indent.count..<(limit + 1)).last { rest[$0] == " " }
            if cut == nil { cut = rest.indices.dropFirst(indent.count).first { rest[$0] == " " } }
            guard let at = cut else { break }
            var head = Array(rest[..<at])
            while head.last == " " { head.removeLast() }
            var tail = rest[(at + 1)...].drop { $0 == " " }
            guard !tail.isEmpty, !head.isEmpty else { break }
            pieces.append(String(head))
            tail = Array(indent)[...] + tail
            rest = Array(tail)
        }
        pieces.append(String(rest))
        return pieces
    }
}
