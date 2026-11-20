import Foundation

/// The number ⌃A and ⌃X change, and what it becomes (ROADMAP C12 item 5). Pure.
enum VimNumber {
    /// The first number on `line` that ends at or after `column` (characters), and its
    /// text after adding `amount`. Hex `0x…` and binary `0b…` keep their prefix, width and
    /// (hex) letter case; decimal keeps leading zeros and takes a "-" right before it as
    /// its sign. Nil when there's no number there.
    static func add(_ amount: Int, in line: String, at column: Int) -> (range: Range<Int>, text: String)? {
        let characters = Array(line)
        let regex = try! NSRegularExpression(pattern: "0[xX][0-9a-fA-F]+|0[bB][01]+|-?[0-9]+")
        let ns = line as NSString
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: line) else { continue }
            let lower = line.distance(from: line.startIndex, to: range.lowerBound)
            let upper = line.distance(from: line.startIndex, to: range.upperBound)
            guard upper - 1 >= column else { continue }
            let token = String(characters[lower..<upper])
            return ((lower..<upper), changed(token, by: amount))
        }
        return nil
    }

    /// The token after adding `amount`, with vim's arithmetic (do_addsub): unsigned 64
    /// bits and a separate sign; a number too big to read is taken as the largest and not
    /// changed; decimal wraps through the sign, hex and binary wrap around.
    static func changed(_ token: String, by amount: Int) -> String {
        let lower = token.lowercased()
        let step = amount.magnitude
        if lower.hasPrefix("0x") || lower.hasPrefix("0b") {
            let radix = lower.hasPrefix("0x") ? 16 : 2
            let digits = String(token.dropFirst(2))
            var value = UInt64(digits, radix: radix) ?? .max
            if UInt64(digits, radix: radix) != nil { value = amount >= 0 ? value &+ UInt64(step) : value &- UInt64(step) }
            var text = String(value, radix: radix)
            // Hex letters take the case of the last letter written.
            if radix == 16, digits.last(where: \.isLetter)?.isUppercase == true { text = text.uppercased() }
            text = String(repeating: "0", count: max(digits.count - text.count, 0)) + text
            return String(token.prefix(2)) + text
        }
        var negative = token.hasPrefix("-")
        let digits = negative ? String(token.dropFirst()) : token
        var value = UInt64(digits) ?? .max
        if UInt64(digits) != nil {
            let subtract = (amount < 0) != negative
            let old = value
            value = subtract ? value &- UInt64(step) : value &+ UInt64(step)
            if subtract, value > old {
                value = 1 &+ ~value
                negative.toggle()
            } else if !subtract, value < old {
                value = ~value
                negative.toggle()
            }
        }
        if value == 0 { negative = false }
        var text = String(value)
        // Leading zeros keep the number's width.
        if digits.hasPrefix("0"), digits.count > 1 { text = String(repeating: "0", count: max(digits.count - text.count, 0)) + text }
        return (negative ? "-" : "") + text
    }
}
