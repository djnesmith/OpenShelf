import Foundation

/// A key as the vim keymap sees it.
enum VimKey: Equatable, Sendable {
    case char(Character)
    case ctrl(Character)
    case escape, enter, backspace
    case left, right, up, down

    /// "dw" → [d, w], for tests and for replaying keys.
    static func keys(_ text: String) -> [VimKey] { text.map(VimKey.char) }
}

enum VimMode: Equatable, Sendable {
    case normal, insert, visual, visualLine
    /// Typing after ":", "/" or "?".
    case commandLine
}

/// What the window does after a key.
enum VimEffect: Equatable, Sendable {
    case finish, cancel
}

/// Text taken by a yank or delete. Linewise text pastes as whole lines.
struct VimRegister: Equatable, Sendable {
    var text: String
    var linewise: Bool
}

/// The Edit window's vim keymap: normal, insert, visual and visual line
/// modes, counts, motions, operators, search and a few ex commands, over a
/// plain text buffer. It has no view, so every key is testable; the window
/// feeds it keys and shows `text`, `cursor` and `selection`.
struct VimEngine {
    private(set) var text: [Character]
    /// A character index. In normal mode it sits on a character (or at the
    /// start of an empty line); in insert mode it is between characters.
    private(set) var cursor = 0
    private(set) var mode = VimMode.normal
    /// The other end of a visual selection.
    private(set) var anchor = 0
    /// What the command line shows, ":" or "/" first.
    private(set) var commandLine = ""
    /// A note for the status line, cleared by the next key.
    private(set) var message: String?
    /// The unnamed register.
    private(set) var register = VimRegister(text: "", linewise: false)

    private let original: [Character]
    private var pending: [VimKey] = []
    /// Earlier texts as strings, which take far less memory than [Character].
    private var undoStack: [(text: String, cursor: Int)] = []
    private var redoStack: [(text: String, cursor: Int)] = []
    /// The column j and k aim for; Int.max after $.
    private var wantedColumn: Int?
    private var lastFind: (command: Character, target: Character)?
    private var lastSearch: (pattern: String, forward: Bool, wholeWord: Bool)?
    /// The text when insert mode began, to drop an insert that changed nothing.
    private var insertStartText: [Character]?

    /// The largest count; 999999, as typed, times another 999999 stays far from overflow.
    static let maxCount = 999_999
    /// Changes undo remembers, as vim's default 'undolevels'.
    static let undoLimit = 1000

    init(_ text: String) {
        self.text = Array(text)
        original = self.text
    }

    var string: String { String(text) }
    var isChanged: Bool { text != original }

    /// The characters a visual selection covers, as a half-open range.
    var selection: Range<Int>? {
        switch mode {
        case .visual:
            let (low, high) = (min(anchor, cursor), max(anchor, cursor))
            return low..<min(high + 1, text.count)
        case .visualLine:
            let low = lineStart(min(anchor, cursor))
            return low..<lineEndIncludingBreak(max(anchor, cursor))
        default:
            return nil
        }
    }

    // MARK: - Keys

    /// Handles one key. Returns `.finish` or `.cancel` when the window should close.
    mutating func handle(_ key: VimKey) -> VimEffect? {
        message = nil
        switch mode {
        case .insert: handleInsert(key); return nil
        case .commandLine: return handleCommandLine(key)
        case .normal, .visual, .visualLine:
            if pending.isEmpty, let arrow = arrowMotion(key) {
                _ = runMotion(arrow, count: 1)
                return nil
            }
            pending.append(key)
            switch parse(pending) {
            case .incomplete: return nil
            case .invalid: pending = []; return nil
            case .done(let command):
                pending = []
                return run(command)
            }
        }
    }

    mutating func handle(_ keys: [VimKey]) -> VimEffect? {
        var effect: VimEffect?
        for key in keys { effect = handle(key) ?? effect }
        return effect
    }

    /// Takes over text typed in the window while in insert mode, where the
    /// text view does the typing itself.
    mutating func syncInsert(text newText: String, cursor newCursor: Int) {
        // Pasted Windows line breaks become "\n", which is what vim's lines end in.
        text = Array(newText.replacingOccurrences(of: "\r\n", with: "\n"))
        cursor = min(max(newCursor, 0), text.count)
    }

    /// Moves the cursor where a click put it; a click leaves visual mode.
    mutating func click(at position: Int) {
        pending = []
        if inVisual { mode = .normal }
        cursor = min(max(position, 0), text.count)
        wantedColumn = nil
        clampCursor()
    }

    /// What the status line names the mode.
    var modeName: String {
        switch mode {
        case .normal: "NORMAL"
        case .insert: "INSERT"
        case .visual: "VISUAL"
        case .visualLine: "VISUAL LINE"
        case .commandLine: "NORMAL"
        }
    }

    private func arrowMotion(_ key: VimKey) -> Motion? {
        switch key {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        default: nil
        }
    }

    // MARK: - Insert mode

    private mutating func handleInsert(_ key: VimKey) {
        switch key {
        case .escape, .ctrl("["), .ctrl("c"):
            leaveInsert()
        case .char(let character):
            text.insert(character, at: cursor)
            cursor += 1
        case .enter:
            text.insert("\n", at: cursor)
            cursor += 1
        case .backspace:
            if cursor > 0 {
                text.remove(at: cursor - 1)
                cursor -= 1
            }
        case .left: cursor = max(cursor - 1, 0)
        case .right: cursor = min(cursor + 1, text.count)
        case .up, .down:
            let line = lineIndex(cursor) + (key == .up ? -1 : 1)
            guard line >= 0, line < lineStarts.count else { return }
            let column = cursor - lineStart(cursor)
            cursor = min(lineStarts[line] + column, lineEnd(lineStarts[line]))
        case .ctrl: break
        }
    }

    private mutating func enterInsert(at position: Int) {
        checkpoint(at: position)
        insertStartText = text
        cursor = position
        mode = .insert
    }

    private mutating func leaveInsert() {
        if let start = insertStartText, start == text { undoStack.removeLast() }
        insertStartText = nil
        mode = .normal
        if cursor > lineStart(cursor) { cursor -= 1 }
        clampCursor()
    }

    // MARK: - Command line

    private mutating func handleCommandLine(_ key: VimKey) -> VimEffect? {
        switch key {
        case .escape, .ctrl("["), .ctrl("c"):
            commandLine = ""
            mode = .normal
        case .backspace:
            commandLine.removeLast()
            if commandLine.isEmpty { mode = .normal }
        case .char(let character):
            commandLine.append(character)
        case .enter:
            let line = commandLine
            commandLine = ""
            mode = .normal
            return runCommandLine(line)
        default:
            break
        }
        return nil
    }

    private mutating func runCommandLine(_ line: String) -> VimEffect? {
        guard let prefix = line.first else { return nil }
        let body = String(line.dropFirst())
        if prefix == "/" || prefix == "?" {
            let pattern = body.isEmpty ? lastSearch?.pattern ?? "" : body
            guard !pattern.isEmpty else { return nil }
            lastSearch = (pattern, prefix == "/", false)
            _ = runMotion(.searchNext(reverse: false), count: 1)
            return nil
        }
        let command = body.trimmingCharacters(in: .whitespaces)
        switch command {
        case "w", "wq", "x", "wq!", "x!", "w!": return .finish
        case "q!": return .cancel
        case "q":
            if isChanged {
                message = "E37: No write since last change (add ! to override)"
                return nil
            }
            return .cancel
        default:
            if let number = Int(command) {
                cursor = firstNonBlank(lineStarts[min(max(number, 1), lineStarts.count) - 1])
                wantedColumn = nil
            } else if !command.isEmpty {
                message = "E492: Not an editor command: \(command)"
            }
            return nil
        }
    }

    // MARK: - Parsing

    enum Motion: Equatable {
        case left, right, up, down
        case wordForward(big: Bool), wordBackward(big: Bool), wordEnd(big: Bool)
        case lineStart, firstNonBlank, lineEnd
        /// G (nil: the last line) and gg (nil: the first).
        case goToLine(Int?)
        case find(Character, Character)
        case repeatFind(reverse: Bool)
        case matchingBracket
        case paragraphForward, paragraphBackward
        case searchNext(reverse: Bool)
        case searchWord(forward: Bool)
    }

    enum Operator: Character {
        case delete = "d", change = "c", yank = "y", indent = ">", outdent = "<"
        case upper = "U", lower = "u", toggleCase = "~"
    }

    struct Command {
        var count: Int?
        var action: Action
    }

    enum Action {
        case motion(Motion)
        case operate(Operator, Motion?)
        case simple(String)
    }

    private enum Parse {
        case incomplete, invalid
        case done(Command)
    }

    private var inVisual: Bool { mode == .visual || mode == .visualLine }

    private func parse(_ keys: [VimKey]) -> Parse {
        var index = 0
        func next() -> VimKey? { index < keys.count ? keys[index] : nil }
        func readCount() -> Int? {
            var digits = ""
            while case .char(let c)? = next(), c.isASCII, c.isNumber, !(digits.isEmpty && c == "0") {
                // Digits past the cap are read but dropped, so no count overflows.
                if digits.count < 6 { digits.append(c) }
                index += 1
            }
            return Int(digits)
        }
        let count = readCount()
        guard let key = next() else { return .incomplete }
        index += 1

        if case .ctrl(let c) = key {
            switch c {
            case "r": return .done(Command(count: count, action: .simple("redo")))
            case "[", "c": return .done(Command(count: nil, action: .simple("escape")))
            default: return .invalid
            }
        }
        switch key {
        case .escape: return .done(Command(count: nil, action: .simple("escape")))
        case .backspace: return .done(Command(count: count, action: .motion(.left)))
        case .enter: return .done(Command(count: count, action: .motion(.down)))
        default: break
        }
        guard case .char(let c) = key else { return .invalid }

        // An operator: d, c, y, >, <, g~, gu, gU (or the same in visual mode).
        var op: Operator?
        if let simpleOp = Operator(rawValue: c), [.delete, .change, .yank, .indent, .outdent].contains(simpleOp) {
            op = simpleOp
        } else if c == "g" {
            guard let second = next() else { return .incomplete }
            if case .char(let g) = second, ["~", "u", "U"].contains(g) {
                index += 1
                op = Operator(rawValue: g)
            }
        }
        if let op {
            if inVisual { return .done(Command(count: count, action: .operate(op, nil))) }
            let motionCount = readCount()
            let total = count.map { min($0 * (motionCount ?? 1), Self.maxCount) } ?? motionCount
            guard let doubled = next() else { return .incomplete }
            // dd, cc, yy, >>, <<, g~~, guu, gUU, and gugu-style repeats.
            if case .char(let d) = doubled, d == op.rawValue || (d == "g" && [.toggleCase, .lower, .upper].contains(op)) {
                if d == "g" {
                    index += 1
                    guard let third = next() else { return .incomplete }
                    guard case .char(op.rawValue) = third else { return .invalid }
                }
                return .done(Command(count: total, action: .simple("line\(op.rawValue)")))
            }
            switch parseMotion(keys, &index) {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .done(let motion): return .done(Command(count: total, action: .operate(op, motion)))
            }
        }

        index -= 1
        switch parseMotion(keys, &index) {
        case .incomplete: return .incomplete
        case .done(let motion): return .done(Command(count: count, action: .motion(motion)))
        case .invalid: break
        }
        index += 1

        if inVisual {
            switch c {
            case "x": return .done(Command(count: count, action: .operate(.delete, nil)))
            case "s": return .done(Command(count: count, action: .operate(.change, nil)))
            case "~": return .done(Command(count: count, action: .operate(.toggleCase, nil)))
            case "u": return .done(Command(count: count, action: .operate(.lower, nil)))
            case "U": return .done(Command(count: count, action: .operate(.upper, nil)))
            case "o", "v", "V", "J": return .done(Command(count: count, action: .simple(String(c))))
            default: return .invalid
            }
        }

        switch c {
        case "x", "X", "s", "S", "D", "C", "Y", "J", "o", "O", "a", "A", "i", "I", "p", "P", "u", "~", "v", "V", ":", "/", "?":
            return .done(Command(count: count, action: .simple(String(c))))
        case "r":
            guard case .char(let target)? = next() else { return next() == nil ? .incomplete : .invalid }
            return .done(Command(count: count, action: .simple("r\(target)")))
        case "Z":
            guard case .char(let second)? = next() else { return next() == nil ? .incomplete : .invalid }
            return ["Z", "Q"].contains(second) ? .done(Command(count: nil, action: .simple("Z\(second)"))) : .invalid
        default:
            return .invalid
        }
    }

    private enum MotionParse {
        case incomplete, invalid
        case done(Motion)
    }

    private func parseMotion(_ keys: [VimKey], _ index: inout Int) -> MotionParse {
        guard index < keys.count else { return .incomplete }
        guard case .char(let c) = keys[index] else {
            switch keys[index] {
            case .left, .backspace: return .done(.left)
            case .right: return .done(.right)
            case .up: return .done(.up)
            case .down, .enter: return .done(.down)
            default: return .invalid
            }
        }
        index += 1
        switch c {
        case "h": return .done(.left)
        case "l", " ": return .done(.right)
        case "j": return .done(.down)
        case "k": return .done(.up)
        case "w", "W": return .done(.wordForward(big: c == "W"))
        case "b", "B": return .done(.wordBackward(big: c == "B"))
        case "e", "E": return .done(.wordEnd(big: c == "E"))
        case "0": return .done(.lineStart)
        case "^": return .done(.firstNonBlank)
        case "$": return .done(.lineEnd)
        case "G": return .done(.goToLine(nil))
        case "%": return .done(.matchingBracket)
        case "}": return .done(.paragraphForward)
        case "{": return .done(.paragraphBackward)
        case ";": return .done(.repeatFind(reverse: false))
        case ",": return .done(.repeatFind(reverse: true))
        case "n": return .done(.searchNext(reverse: false))
        case "N": return .done(.searchNext(reverse: true))
        case "*": return .done(.searchWord(forward: true))
        case "#": return .done(.searchWord(forward: false))
        case "f", "F", "t", "T":
            guard index < keys.count else { return .incomplete }
            guard case .char(let target) = keys[index] else { return .invalid }
            index += 1
            return .done(.find(c, target))
        case "g":
            guard index < keys.count else { return .incomplete }
            guard case .char("g") = keys[index] else { return .invalid }
            index += 1
            return .done(.goToLine(0))
        default:
            index -= 1
            return .invalid
        }
    }

    // MARK: - Running commands

    private mutating func run(_ command: Command) -> VimEffect? {
        switch command.action {
        case .motion(let motion):
            _ = runMotion(Self.resolved(motion, count: command.count), count: command.count ?? 1)
            return nil
        case .operate(let op, let motion):
            wantedColumn = nil
            if let motion {
                operate(op, motion: Self.resolved(motion, count: command.count), count: command.count ?? 1)
            } else if let range = selection {
                let linewise = mode == .visualLine
                let (first, last) = (lineIndex(min(anchor, cursor)), lineIndex(max(anchor, cursor)))
                mode = .normal
                if linewise { applyLines(op, first, last) } else { apply(op, to: range) }
            }
            return nil
        case .simple(let name):
            wantedColumn = nil
            return runSimple(name, count: command.count)
        }
    }

    /// A count before G or gg names the line: G alone is the last line, gg the first.
    private static func resolved(_ motion: Motion, count: Int?) -> Motion {
        guard case .goToLine(let line) = motion else { return motion }
        return .goToLine(count ?? (line == 0 ? 1 : nil))
    }

    /// Moves the cursor. Returns false when the motion found nowhere to go.
    private mutating func runMotion(_ motion: Motion, count: Int) -> Bool {
        guard let target = target(of: motion, count: count, forOperator: false) else { return false }
        cursor = target.position
        switch motion {
        case .up, .down: break
        case .lineEnd: wantedColumn = .max
        default: wantedColumn = nil
        }
        clampCursor()
        return true
    }

    private mutating func runSimple(_ name: String, count: Int?) -> VimEffect? {
        let n = count ?? 1
        if inVisual {
            switch name {
            case "escape": mode = .normal
            case "o": swap(&anchor, &cursor)
            case "J":
                let (low, high) = (min(anchor, cursor), max(anchor, cursor))
                mode = .normal
                cursor = low
                join(count: max(lineIndex(high) - lineIndex(low) + 1, 2))
            case "v", "V":
                let wanted: VimMode = name == "v" ? .visual : .visualLine
                mode = mode == wanted ? .normal : wanted
            default: break
            }
            clampCursor()
            return nil
        }
        switch name {
        case "escape": break
        case "x": operate(.delete, motion: .right, count: n)
        case "X": operate(.delete, motion: .left, count: n)
        case "s": operate(.change, motion: .right, count: n)
        case "S": runLine(.change, count: n)
        case "D": operate(.delete, motion: .lineEnd, count: n)
        case "C": operate(.change, motion: .lineEnd, count: n)
        case "Y": operate(.yank, motion: .lineEnd, count: n)
        case "J": join(count: max(n, 2))
        case "o", "O": openLine(below: name == "o")
        case "i": enterInsert(at: cursor)
        case "a": enterInsert(at: min(cursor + (lineIsEmpty(cursor) ? 0 : 1), lineEnd(cursor)))
        case "A": enterInsert(at: lineEnd(cursor))
        case "I": enterInsert(at: firstNonBlank(lineStart(cursor)))
        case "p", "P": put(after: name == "p", count: n)
        case "u": undo(count: n)
        case "redo": redo(count: n)
        case "~": toggleCaseUnderCursor(count: n)
        case "v", "V":
            anchor = cursor
            mode = name == "v" ? .visual : .visualLine
        case ":", "/", "?":
            mode = .commandLine
            commandLine = name
        case "ZZ": return .finish
        case "ZQ": return .cancel
        default:
            if name.hasPrefix("line"), let op = name.last.flatMap(Operator.init(rawValue:)) {
                runLine(op, count: n)
            } else if name.hasPrefix("r"), name.count == 2, let target = name.last {
                replaceCharacters(with: target, count: n)
            }
        }
        return nil
    }

    // MARK: - Motions

    private enum Kind { case exclusive, inclusive, linewise }

    private struct Target {
        var position: Int
        var kind: Kind
    }

    private mutating func target(of motion: Motion, count: Int, forOperator: Bool) -> Target? {
        let n = text.count
        switch motion {
        case .left:
            return Target(position: max(cursor - count, lineStart(cursor)), kind: .exclusive)
        case .right:
            // An operator, or a visual selection, can take the line break too.
            let end = forOperator || inVisual ? lineEnd(cursor) : max(lineEnd(cursor) - 1, lineStart(cursor))
            return Target(position: min(cursor + count, end), kind: .exclusive)
        case .up, .down:
            // A count past the first or last line stops there; no line to move to fails.
            let here = lineIndex(cursor)
            let line = min(max(here + (motion == .up ? -count : count), 0), lineStarts.count - 1)
            guard line != here else { return nil }
            let column = wantedColumn ?? (cursor - lineStart(cursor))
            if wantedColumn == nil { wantedColumn = column }
            let start = lineStarts[line]
            let end = lineEnd(start)
            return Target(position: column == .max ? max(end - 1, start) : min(start + column, max(end - 1, start)), kind: .linewise)
        case .wordForward(let big):
            var position = cursor
            for _ in 0..<count { position = wordForward(from: position, big: big) }
            return Target(position: position, kind: .exclusive)
        case .wordBackward(let big):
            var position = cursor
            for _ in 0..<count { position = wordBackward(from: position, big: big) }
            return Target(position: position, kind: .exclusive)
        case .wordEnd(let big):
            // A count goes as far as there are words.
            var position = cursor
            var reachedEnd = false
            for _ in 0..<count {
                let next = wordEnd(from: position, big: big)
                if next >= n { reachedEnd = true; break }
                position = next
            }
            if reachedEnd {
                // An operator still takes the text up to the end; the cursor
                // alone reaches a last empty line, or the last word end found.
                // At the very end, ce still starts an (empty) change.
                if forOperator { return n - 1 >= cursor ? Target(position: n - 1, kind: .inclusive) : Target(position: cursor, kind: .exclusive) }
                if text.last == "\n", cursor < n { return Target(position: n, kind: .exclusive) }
                if position == cursor { return nil }
            }
            return Target(position: position, kind: .inclusive)
        case .lineStart:
            return Target(position: lineStart(cursor), kind: .exclusive)
        case .firstNonBlank:
            return Target(position: firstNonBlank(lineStart(cursor)), kind: .exclusive)
        case .lineEnd:
            let line = min(lineIndex(cursor) + count - 1, lineStarts.count - 1)
            let end = lineEnd(lineStarts[line])
            // d$ on an empty line has nothing to take; v$ takes the line break.
            if end == lineStarts[line] || inVisual { return Target(position: end, kind: forOperator ? .exclusive : .inclusive) }
            return Target(position: end - 1, kind: .inclusive)
        case .goToLine(let number):
            let line = min(max(number ?? lineStarts.count, 1), lineStarts.count) - 1
            return Target(position: firstNonBlank(lineStarts[line]), kind: .linewise)
        case .find(let command, let target):
            lastFind = (command, target)
            return find(command, target, count: count, repeating: false).map { Target(position: $0, kind: command == "f" || command == "t" ? .inclusive : .exclusive) }
        case .repeatFind(let reverse):
            guard let last = lastFind else { return nil }
            let command: Character = reverse ? (last.command.isUppercase ? Character(last.command.lowercased()) : Character(last.command.uppercased())) : last.command
            return find(command, last.target, count: count, repeating: true).map { Target(position: $0, kind: command == "f" || command == "t" ? .inclusive : .exclusive) }
        case .matchingBracket:
            return matchingBracket().map { Target(position: $0, kind: .inclusive) }
        case .paragraphForward, .paragraphBackward:
            let starts = lineStarts
            func blank(_ line: Int) -> Bool {
                text[starts[line]..<(line + 1 < starts.count ? starts[line + 1] - 1 : n)].allSatisfy { $0 == " " || $0 == "\t" }
            }
            var line = lineIndex(cursor)
            let forward = motion == .paragraphForward
            let step = forward ? 1 : -1
            for _ in 0..<count {
                while line + step >= 0, line + step < starts.count, blank(line) { line += step }
                while line + step >= 0, line + step < starts.count, !blank(line + step) { line += step }
                if line + step >= 0, line + step < starts.count { line += step } else {
                    return Target(position: forward ? n : 0, kind: .exclusive)
                }
            }
            return Target(position: starts[line], kind: .exclusive)
        case .searchNext(let reverse):
            guard let search = lastSearch else {
                message = "E35: No previous regular expression"
                return nil
            }
            var position = cursor
            for _ in 0..<count {
                guard let found = self.search(search.pattern, from: position, forward: search.forward != reverse, wholeWord: search.wholeWord) else {
                    message = "E486: Pattern not found: \(search.pattern)"
                    return nil
                }
                position = found
            }
            return Target(position: position, kind: .exclusive)
        case .searchWord(let forward):
            guard let word = wordUnderCursor() else {
                message = "E348: No string under cursor"
                return nil
            }
            lastSearch = (word, forward, true)
            return target(of: .searchNext(reverse: false), count: count, forOperator: forOperator)
        }
    }

    private func characterClass(_ position: Int, big: Bool) -> Int {
        let c = text[position]
        if c.isWhitespace { return 0 }
        if big { return 1 }
        return c.isLetter || c.isNumber || c == "_" ? 1 : 2
    }

    private func isEmptyLine(at position: Int) -> Bool {
        position < text.count ? text[position] == "\n" && (position == 0 || text[position - 1] == "\n") : position == lineStart(position)
    }

    private func wordForward(from start: Int, big: Bool) -> Int {
        var position = start
        let n = text.count
        guard position < n else { return n }
        let kind = characterClass(position, big: big)
        if kind != 0 { while position < n, characterClass(position, big: big) == kind { position += 1 } }
        while position < n, characterClass(position, big: big) == 0 {
            if text[position] == "\n" {
                position += 1
                if position < n, text[position] == "\n" { break }
            } else {
                position += 1
            }
        }
        return position
    }

    private func wordBackward(from start: Int, big: Bool) -> Int {
        var position = start
        guard position > 0 else { return 0 }
        position -= 1
        while position > 0, characterClass(position, big: big) == 0, !isEmptyLine(at: position) { position -= 1 }
        if isEmptyLine(at: position) || characterClass(position, big: big) == 0 { return position }
        let kind = characterClass(position, big: big)
        while position > 0, characterClass(position - 1, big: big) == kind { position -= 1 }
        return position
    }

    private func wordEnd(from start: Int, big: Bool) -> Int {
        var position = start + 1
        let n = text.count
        while position < n, characterClass(position, big: big) == 0 { position += 1 }
        guard position < n else { return n }
        let kind = characterClass(position, big: big)
        while position + 1 < n, characterClass(position + 1, big: big) == kind { position += 1 }
        return position
    }

    private func find(_ command: Character, _ target: Character, count: Int, repeating: Bool) -> Int? {
        let start = lineStart(cursor)
        let end = lineEnd(cursor)
        var position = cursor
        let forward = command == "f" || command == "t"
        let till = command == "t" || command == "T"
        for iteration in 0..<count {
            // ; after t starts one further on, or it would find the same place.
            let skip = till && (repeating || iteration > 0) ? 1 : 0
            if forward {
                guard let found = (min(position + 1 + skip, end)..<end).first(where: { text[$0] == target }) else { return nil }
                position = found
            } else {
                guard let found = (start..<max(position - skip, start)).last(where: { text[$0] == target }) else { return nil }
                position = found
            }
        }
        if till { position += forward ? -1 : 1 }
        return position
    }

    private func matchingBracket() -> Int? {
        let pairs: [Character: (Character, Bool)] = ["(": (")", true), "[": ("]", true), "{": ("}", true), ")": ("(", false), "]": ("[", false), "}": ("{", false)]
        guard let start = (cursor..<lineEnd(cursor)).first(where: { pairs[text[$0]] != nil }) else { return nil }
        let open = text[start]
        guard let (close, forward) = pairs[open] else { return nil }
        var depth = 0
        var position = start
        while position >= 0, position < text.count {
            if text[position] == open { depth += 1 } else if text[position] == close { depth -= 1 }
            if depth == 0 { return position }
            position += forward ? 1 : -1
        }
        return nil
    }

    private func wordUnderCursor() -> String? {
        guard cursor < text.count, characterClass(cursor, big: false) == 1 else {
            // vim takes the next word on the line.
            guard let next = (cursor..<lineEnd(cursor)).first(where: { characterClass($0, big: false) == 1 }) else { return nil }
            var copy = self
            copy.cursor = next
            return copy.wordUnderCursor()
        }
        var low = cursor, high = cursor
        while low > 0, characterClass(low - 1, big: false) == 1 { low -= 1 }
        while high + 1 < text.count, characterClass(high + 1, big: false) == 1 { high += 1 }
        return String(text[low...high])
    }

    /// The next match of `pattern` after (or before) `position`, wrapping
    /// around. Lowercase patterns ignore case (smartcase).
    private func search(_ pattern: String, from position: Int, forward: Bool, wholeWord: Bool) -> Int? {
        let needle = Array(pattern)
        let ignoreCase = !wholeWord && !pattern.contains(where: \.isUppercase)
        let n = text.count
        guard !needle.isEmpty, needle.count <= n else { return nil }
        func matches(_ at: Int) -> Bool {
            guard at + needle.count <= n else { return false }
            for i in 0..<needle.count {
                let a = text[at + i], b = needle[i]
                if ignoreCase ? a.lowercased() != b.lowercased() : a != b { return false }
            }
            if wholeWord {
                if at > 0, characterClass(at - 1, big: false) == 1 { return false }
                if at + needle.count < n, characterClass(at + needle.count, big: false) == 1 { return false }
            }
            return true
        }
        for step in 1...n {
            let at = forward ? (position + step) % n : ((position - step) % n + n) % n
            if matches(at) { return at }
        }
        return nil
    }

    // MARK: - Operators

    private mutating func operate(_ op: Operator, motion: Motion, count: Int) {
        let start = cursor
        if case .wordForward(let big) = motion {
            // cw on a word changes to its end, not up to the next word.
            if op == .change, start < text.count, characterClass(start, big: big) != 0 {
                var end = start - 1
                for _ in 0..<count { end = wordEnd(from: end, big: big) }
                apply(op, from: start, to: Target(position: min(end, text.count - 1), kind: .inclusive))
                return
            }
            // When the last word moved over ends a line, the operator stops
            // at that line's end rather than taking the line break too.
            var (previous, position) = (start, start)
            for _ in 0..<count { (previous, position) = (position, wordForward(from: position, big: big)) }
            if lineIndex(position) > lineIndex(previous), lineEnd(previous) > previous { position = lineEnd(previous) }
            apply(op, from: start, to: Target(position: position, kind: .exclusive))
            return
        }
        guard let target = target(of: motion, count: count, forOperator: true) else { return }
        apply(op, from: start, to: target)
    }

    private mutating func apply(_ op: Operator, from start: Int, to target: Target) {
        switch target.kind {
        case .linewise:
            applyLines(op, lineIndex(min(start, target.position)), lineIndex(max(start, target.position)))
        case .inclusive, .exclusive:
            let low = min(start, target.position)
            var high = max(start, target.position)
            if target.kind == .inclusive { high = min(high + 1, text.count) }
            // An exclusive motion that ends at the start of a later line ends
            // at the line before instead, and takes whole lines when it began
            // in the indentation (:help exclusive-linewise).
            if target.kind == .exclusive, high == lineStart(high), lineIndex(high) > lineIndex(low) {
                if isInIndent(low) {
                    applyLines(op, lineIndex(low), lineIndex(high) - 1)
                    return
                }
                high -= 1
            }
            // A delete over several lines that leaves only blanks on its last
            // line, and began in the indentation, deletes whole lines.
            if op == .delete, lineIndex(high) > lineIndex(low), isInIndent(low),
               text[high..<lineEnd(high)].allSatisfy({ $0 == " " || $0 == "\t" }) {
                applyLines(op, lineIndex(low), lineIndex(high))
                return
            }
            guard high > low || op == .change else { return }
            if op == .indent || op == .outdent {
                applyLines(op, lineIndex(low), lineIndex(max(high - 1, low)))
            } else {
                apply(op, to: low..<high)
            }
        }
    }

    /// dd, cc, yy, >>, <<, g~~, guu, gUU on `count` lines.
    private mutating func runLine(_ op: Operator, count: Int) {
        let line = lineIndex(cursor)
        guard count == 1 || line + 1 < lineStarts.count else { return }
        let last = min(line + count - 1, lineStarts.count - 1)
        applyLines(op, line, last)
    }

    /// An operator on whole lines, `first` through `last`.
    private mutating func applyLines(_ op: Operator, _ first: Int, _ last: Int) {
        let starts = lineStarts
        let start = starts[first]
        let bodyEnd = lineEnd(starts[last])
        let taken = String(text[start..<bodyEnd]) + "\n"
        switch op {
        case .yank:
            register = VimRegister(text: taken, linewise: true)
            // yy and yj leave the cursor; yk takes it up to the first line.
            if lineIndex(cursor) != first { cursor = start + min(cursor - lineStart(cursor), max(bodyEnd - start, 0)) }
        case .delete:
            register = VimRegister(text: taken, linewise: true)
            checkpoint(at: start)
            if last + 1 < starts.count {
                text.removeSubrange(start..<starts[last + 1])
            } else {
                // The last line takes the line break before it.
                text.removeSubrange(max(start - 1, 0)..<text.count)
            }
            cursor = firstNonBlank(lineStarts[min(first, lineStarts.count - 1)])
        case .change:
            register = VimRegister(text: taken, linewise: true)
            checkpoint(at: start)
            // cc keeps one line, emptied but for its indentation.
            let indent = Array(text[start..<firstNonBlank(start)])
            text.replaceSubrange(start..<bodyEnd, with: indent)
            cursor = start + indent.count
            mode = .insert
            return
        case .indent, .outdent, .upper, .lower, .toggleCase:
            checkpoint(at: start)
            let block = String(text[start..<bodyEnd])
            text.replaceSubrange(start..<bodyEnd, with: Array(transformed(block, op)))
            // Indenting goes to the first non-blank; a case change no further right.
            cursor = op == .indent || op == .outdent ? firstNonBlank(start) : min(cursor, firstNonBlank(start))
            if string == undoStack.last?.text { undoStack.removeLast() }
        }
        wantedColumn = nil
        clampCursor()
    }

    /// An operator on the characters in `range`.
    private mutating func apply(_ op: Operator, to range: Range<Int>) {
        let taken = String(text[range])
        switch op {
        case .yank:
            register = VimRegister(text: taken, linewise: false)
            cursor = range.lowerBound
        case .delete, .change:
            // C on an empty line takes nothing, and keeps what was taken before.
            if !range.isEmpty { register = VimRegister(text: taken, linewise: false) }
            checkpoint(at: range.lowerBound)
            text.removeSubrange(range)
            cursor = range.lowerBound
            if op == .change {
                mode = .insert
                return
            }
        case .indent, .outdent, .upper, .lower, .toggleCase:
            checkpoint(at: range.lowerBound)
            text.replaceSubrange(range, with: Array(transformed(taken, op)))
            cursor = range.lowerBound
            if string == undoStack.last?.text { undoStack.removeLast() }
        }
        wantedColumn = nil
        clampCursor()
    }

    private func transformed(_ block: String, _ op: Operator) -> String {
        switch op {
        case .indent: TextTransforms.indent(block)
        case .outdent: TextTransforms.outdent(block)
        case .upper: block.uppercased()
        case .lower: block.lowercased()
        case .toggleCase: block.map { $0.isUppercase ? $0.lowercased() : $0.uppercased() }.joined()
        default: block
        }
    }

    // MARK: - Other changes

    private mutating func openLine(below: Bool) {
        let start = lineStart(cursor)
        let indent = Array(text[start..<firstNonBlank(start)])
        if below {
            let end = lineEnd(cursor)
            enterInsert(at: end)
            text.insert(contentsOf: ["\n"] + indent, at: end)
            cursor = end + 1 + indent.count
        } else {
            enterInsert(at: start)
            text.insert(contentsOf: indent + ["\n"], at: start)
            cursor = start + indent.count
        }
    }

    private mutating func join(count: Int) {
        let line = lineIndex(cursor)
        guard line + 1 < lineStarts.count else { return }
        checkpoint()
        for _ in 0..<(count - 1) {
            let end = lineEnd(cursor)
            guard end < text.count else { break }
            var next = end + 1
            while next < text.count, text[next] == " " || text[next] == "\t" { next += 1 }
            // One space between, unless either side is empty, the line already
            // ends in a blank, or the next starts with ")". Nothing else is trimmed.
            let endsInBlank = end > lineStart(end) && (text[end - 1] == " " || text[end - 1] == "\t")
            let joinsWithSpace = end > lineStart(end) && !endsInBlank && next < text.count && text[next] != "\n" && text[next] != ")"
            text.replaceSubrange(end..<next, with: joinsWithSpace ? [" "] : [])
            cursor = end
        }
        clampCursor()
    }

    private mutating func put(after: Bool, count: Int) {
        guard !register.text.isEmpty else { return }
        checkpoint()
        let pasted = Array(String(repeating: register.text, count: count))
        if register.linewise {
            let at = after ? lineEndIncludingBreak(cursor) : lineStart(cursor)
            if after, lineIndex(cursor) == lineStarts.count - 1 {
                // After the last line, which has no line break of its own.
                text.insert(contentsOf: ["\n"] + pasted.dropLast(), at: at)
                cursor = firstNonBlank(at + 1)
            } else {
                text.insert(contentsOf: pasted, at: at)
                cursor = firstNonBlank(at)
            }
        } else {
            let at = after && !lineIsEmpty(cursor) ? min(cursor + 1, text.count) : cursor
            text.insert(contentsOf: pasted, at: at)
            // Text that spans lines leaves the cursor at its start.
            cursor = pasted.contains("\n") ? at : at + pasted.count - 1
        }
        clampCursor()
    }

    private mutating func replaceCharacters(with replacement: Character, count: Int) {
        let end = lineEnd(cursor)
        guard cursor + count <= end else { return }
        checkpoint()
        if replacement == "\r" || replacement == "\n" {
            text.replaceSubrange(cursor..<(cursor + count), with: ["\n"])
            cursor += 1
        } else {
            text.replaceSubrange(cursor..<(cursor + count), with: Array(repeating: replacement, count: count))
            cursor += count - 1
        }
    }

    private mutating func toggleCaseUnderCursor(count: Int) {
        let end = min(cursor + count, lineEnd(cursor))
        guard end > cursor else { return }
        checkpoint()
        for i in cursor..<end {
            let c = text[i]
            let swapped = c.isUppercase ? c.lowercased() : c.uppercased()
            if swapped.count == 1 { text[i] = Character(swapped) }
        }
        cursor = min(end, max(lineEnd(cursor) - 1, lineStart(cursor)))
    }

    // MARK: - Undo

    /// Saves the text for undo. `position` is where the change begins,
    /// where undo leaves the cursor, as vim does.
    private mutating func checkpoint(at position: Int? = nil) {
        undoStack.append((string, position ?? cursor))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack = []
    }

    private mutating func undo(count: Int) {
        for _ in 0..<count {
            guard let last = undoStack.popLast() else {
                message = "Already at oldest change"
                break
            }
            redoStack.append((string, last.cursor))
            text = Array(last.text)
            cursor = last.cursor
        }
        clampCursor()
    }

    private mutating func redo(count: Int) {
        for _ in 0..<count {
            guard let next = redoStack.popLast() else {
                message = "Already at newest change"
                break
            }
            undoStack.append((string, next.cursor))
            text = Array(next.text)
            cursor = next.cursor
        }
        clampCursor()
    }

    // MARK: - Lines

    private var lineStarts: [Int] {
        [0] + text.indices.filter { text[$0] == "\n" }.map { $0 + 1 }
    }

    private func lineIndex(_ position: Int) -> Int {
        text[..<min(position, text.count)].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private func lineStart(_ position: Int) -> Int {
        var i = min(position, text.count)
        while i > 0, text[i - 1] != "\n" { i -= 1 }
        return i
    }

    private func lineEnd(_ position: Int) -> Int {
        var i = lineStart(position)
        while i < text.count, text[i] != "\n" { i += 1 }
        return i
    }

    private func lineEndIncludingBreak(_ position: Int) -> Int {
        min(lineEnd(position) + 1, text.count)
    }

    private func firstNonBlank(_ lineStartPosition: Int) -> Int {
        var i = lineStartPosition
        while i < text.count, text[i] == " " || text[i] == "\t" { i += 1 }
        return i
    }

    /// Only blanks come before `position` on its line.
    private func isInIndent(_ position: Int) -> Bool {
        text[lineStart(position)..<position].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func lineIsEmpty(_ position: Int) -> Bool { lineStart(position) == lineEnd(position) }

    /// Normal and visual mode keep the cursor on a character of its line.
    private mutating func clampCursor() {
        guard mode != .insert else { return }
        cursor = min(max(cursor, 0), text.count)
        let start = lineStart(cursor)
        cursor = min(max(cursor, start), inVisual ? lineEnd(cursor) : max(lineEnd(cursor) - 1, start))
    }
}
