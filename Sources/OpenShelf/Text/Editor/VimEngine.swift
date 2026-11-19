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
    /// `:set wrap` (true), `:set nowrap` (false), `:set wrap!` or `:set invwrap` (nil: toggle).
    case wrap(Bool?)
}

/// The system clipboard as the engine sees it, so tests need none.
struct VimClipboard {
    var read: () -> String? = { nil }
    var write: (String) -> Void = { _ in }
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
    /// Registers "a to "z and "0 (the last yank).
    private(set) var registers: [Character: VimRegister] = [:]
    /// The system clipboard behind "+ and "*; the window connects it.
    var clipboard = VimClipboard()
    /// David's rule for the Edit window: yanks also go on the Mac clipboard,
    /// deletes and changes never do, and p and P with no register always
    /// paste the Mac clipboard. Off (plain vim) unless the window turns it on.
    var usesSystemClipboard = false

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
    /// The text once insert mode began, after any automatic text (o's line
    /// break, cc's indentation), to work out what was typed for ".".
    private var insertBaseline: [Character] = []
    /// The register named for the command being run ("a, "+, "_).
    private var activeRegister: Character?
    /// The last change, as keys, for "." to run again.
    private var lastChange: (count: Int?, keys: [VimKey])?
    /// A change that went into insert mode; its typing is added on Esc.
    private var changeInProgress: (count: Int?, keys: [VimKey])?
    private var isRepeating = false
    /// What ys wraps its range in: the opening and closing text.
    private var surroundPair = (open: "", close: "")
    /// 3ix<Esc> types "x" three times: the count of the insert command.
    private var insertCount = 1
    /// The register a macro is being recorded into (q{a-z}), for the status line.
    private(set) var recording: Character?
    private var recordedKeys: [VimKey] = []
    /// Insert mode was typed by the text view, so the recording needs the text added at Esc.
    private var viewTyped = false
    /// The last macro played, for @@.
    private var lastMacro: Character?
    /// A macro is playing; @a inside it queues its keys next, as vim's typeahead does.
    private var playDepth = 0
    private var macroBudget = 0
    /// Keys still to play, last first.
    private var macroQueue: [VimKey] = []
    /// The last command failed (a motion went nowhere, a target wasn't found); a macro stops there.
    private var failed = false
    /// How many old undo states have been dropped, so a macro's own can be found.
    private var undoTrimmed = 0
    /// Keys a macro may play in all, recursion included.
    static let macroKeyLimit = 100_000

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
        if recording != nil, playDepth == 0, !isRepeating { recordedKeys.append(key) }
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
            case .invalid:
                pending = []
                failed = true
                return nil
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
        viewTyped = true
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
        beginInsert()
    }

    /// What was typed since insert mode began: the text between what stayed
    /// the same at either end. With `single`, the count's repeats are left out.
    private func typedSinceInsert(single count: Int? = nil) -> [Character] {
        let prefix = zip(insertBaseline, text).prefix { $0 == $1 }.count
        let room = min(insertBaseline.count, text.count) - prefix
        let suffix = zip(insertBaseline.reversed(), text.reversed()).prefix { $0 == $1 }.count
        let typed = Array(text[prefix..<(text.count - min(suffix, room))])
        guard let count, count > 1, typed.count % count == 0 else { return typed }
        return Array(typed.prefix(typed.count / count))
    }

    private mutating func beginInsert() {
        mode = .insert
        insertBaseline = text
        viewTyped = false
    }

    private mutating func leaveInsert() {
        let repeats = insertCount
        if insertCount > 1 {
            let typed = typedSinceInsert()
            let more = Array(repeating: typed, count: insertCount - 1).flatMap { $0 }
            text.insert(contentsOf: more, at: cursor)
            cursor += more.count
        }
        insertCount = 1
        if let start = insertStartText, start == text { undoStack.removeLast() }
        insertStartText = nil
        // The text view typed this insert, so the recording gets the text, before its Esc.
        if recording != nil, viewTyped, playDepth == 0, !isRepeating {
            let esc = recordedKeys.popLast()
            recordedKeys += typedSinceInsert(single: repeats).map(VimKey.char)
            if let esc { recordedKeys.append(esc) }
        }
        viewTyped = false
        // "." types again what was typed: the text between what stayed the same at either end.
        if let change = changeInProgress, !isRepeating {
            lastChange = (change.count, change.keys + typedSinceInsert(single: repeats).map(VimKey.char) + [.escape])
        }
        changeInProgress = nil
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
            guard !pattern.isEmpty else {
                message = "E35: No previous regular expression"
                failed = true
                return nil
            }
            lastSearch = (pattern, prefix == "/", false)
            _ = runMotion(.searchNext(reverse: false), count: 1)
            return nil
        }
        let command = body.trimmingCharacters(in: .whitespaces)
        switch command {
        case "w", "wq", "x", "wq!", "x!", "w!": return .finish
        case "set wrap": return .wrap(true)
        case "set nowrap": return .wrap(false)
        case "set wrap!", "set invwrap": return .wrap(nil)
        case "q!": return .cancel
        case "q":
            if isChanged {
                message = "E37: No write since last change (add ! to override)"
                failed = true
                return nil
            }
            return .cancel
        default:
            if let number = Int(command) {
                cursor = firstNonBlank(lineStarts[min(max(number, 1), lineStarts.count) - 1])
                wantedColumn = nil
            } else if !command.isEmpty {
                message = "E492: Not an editor command: \(command)"
                failed = true
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
        /// iw, a", i(, ap…: a range around the cursor, after an operator or in visual mode.
        case textObject(inner: Bool, Character)
    }

    enum Operator: Character {
        case delete = "d", change = "c", yank = "y", indent = ">", outdent = "<"
        case upper = "U", lower = "u", toggleCase = "~"
        /// ys: wraps the range in `surroundPair`.
        case surround = "S"
    }

    struct Command {
        var count: Int?
        var action: Action
        var register: Character?
        /// The keys after the count and register, for ".".
        var keys: [VimKey] = []
        /// Where a count between an operator and its motion sits (d3w), so
        /// "." can leave it out and use the total count instead.
        var innerCount: Range<Int>?

        init(count: Int?, action: Action) {
            self.count = count
            self.action = action
        }
    }

    enum Action {
        case motion(Motion)
        case operate(Operator, Motion?)
        case simple(String)
        /// vim-surround: ds, cs, ys (nil motion: yss) and visual S.
        case deleteSurround(Character)
        case changeSurround(Character, String)
        case addSurround(Motion?, String)
    }

    private enum Parse {
        case incomplete, invalid
        case done(Command)
    }

    private var inVisual: Bool { mode == .visual || mode == .visualLine }

    /// A count and a register ("a, "+) may come before a command, in either order.
    private func parse(_ keys: [VimKey]) -> Parse {
        var index = 0
        var count = Self.readCount(keys, &index)
        var register: Character?
        if index < keys.count, keys[index] == .char("\"") {
            index += 1
            guard index < keys.count else { return .incomplete }
            guard case .char(let name) = keys[index], Self.isRegisterName(name) else { return .invalid }
            index += 1
            register = name
            if let more = Self.readCount(keys, &index) { count = min((count ?? 1) * more, Self.maxCount) }
        }
        let body = index
        let result = parseCommand(keys, from: index, count: count)
        guard case .done(var command) = result else { return result }
        command.register = register
        // The keys "." runs again, without counts: it puts the total back in front.
        command.keys = keys.indices.filter { $0 >= body && !(command.innerCount?.contains($0) ?? false) }.map { keys[$0] }
        return .done(command)
    }

    /// Digits past the cap are read but dropped, so no count overflows.
    private static func readCount(_ keys: [VimKey], _ index: inout Int) -> Int? {
        var digits = ""
        while index < keys.count, case .char(let c) = keys[index], c.isASCII, c.isNumber, !(digits.isEmpty && c == "0") {
            if digits.count < 6 { digits.append(c) }
            index += 1
        }
        return Int(digits)
    }

    static func isRegisterName(_ name: Character) -> Bool {
        name.isASCII && (name.isLetter || ["\"", "0", "+", "*", "_"].contains(name))
    }

    private func parseCommand(_ keys: [VimKey], from start: Int, count: Int?) -> Parse {
        var index = start
        func next() -> VimKey? { index < keys.count ? keys[index] : nil }
        func readCount() -> Int? { Self.readCount(keys, &index) }
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

        // vim-surround: ds{target}, cs{target}{replacement}, ys{motion}{replacement}, yss{replacement}.
        if !inVisual, ["d", "c", "y"].contains(c), index < keys.count, keys[index] == .char("s") {
            index += 1
            if c == "y" {
                // A count may also come between ys and its motion (ys2w).
                var count = count
                let countStart = index
                if let more = readCount() { count = min((count ?? 1) * more, Self.maxCount) }
                let innerCount = countStart..<index
                guard index < keys.count else { return .incomplete }
                var motion: Motion?
                if keys[index] == .char("s") {
                    index += 1
                } else {
                    switch parseMotion(keys, &index, textObjects: true) {
                    case .incomplete: return .incomplete
                    case .invalid: return .invalid
                    case .done(let parsed): motion = parsed
                    }
                }
                return parseReplacement(keys, &index).map {
                    var command = Command(count: count, action: .addSurround(motion, $0))
                    command.innerCount = innerCount
                    return command
                }
            }
            guard index < keys.count else { return .incomplete }
            guard case .char(let target) = keys[index], Self.surroundTargets.contains(target) else { return .invalid }
            index += 1
            if c == "d" { return .done(Command(count: count, action: .deleteSurround(target))) }
            return parseReplacement(keys, &index).map { Command(count: count, action: .changeSurround(target, $0)) }
        }

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
            let countStart = index
            let motionCount = readCount()
            let innerCount = countStart..<index
            let total = count.map { min($0 * (motionCount ?? 1), Self.maxCount) } ?? motionCount
            guard let doubled = next() else { return .incomplete }
            // dd, cc, yy, >>, <<, g~~, guu, gUU, and gugu-style repeats.
            if case .char(let d) = doubled, d == op.rawValue || (d == "g" && [.toggleCase, .lower, .upper].contains(op)) {
                if d == "g" {
                    index += 1
                    guard let third = next() else { return .incomplete }
                    guard case .char(op.rawValue) = third else { return .invalid }
                }
                var command = Command(count: total, action: .simple("line\(op.rawValue)"))
                command.innerCount = innerCount
                return .done(command)
            }
            switch parseMotion(keys, &index, textObjects: true) {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .done(let motion):
                var command = Command(count: total, action: .operate(op, motion))
                command.innerCount = innerCount
                return .done(command)
            }
        }

        index -= 1
        switch parseMotion(keys, &index, textObjects: inVisual) {
        case .incomplete: return .incomplete
        case .done(let motion): return .done(Command(count: count, action: .motion(motion)))
        case .invalid: break
        }
        index += 1

        if inVisual {
            switch c {
            case "S":
                return parseReplacement(keys, &index).map { Command(count: count, action: .addSurround(nil, $0)) }
            case "x": return .done(Command(count: count, action: .operate(.delete, nil)))
            case "s": return .done(Command(count: count, action: .operate(.change, nil)))
            case "~": return .done(Command(count: count, action: .operate(.toggleCase, nil)))
            case "u": return .done(Command(count: count, action: .operate(.lower, nil)))
            case "U": return .done(Command(count: count, action: .operate(.upper, nil)))
            case "o", "v", "V", "J", "p", "P": return .done(Command(count: count, action: .simple(String(c))))
            case "q" where recording != nil: return .done(Command(count: nil, action: .simple("q")))
            default: return .invalid
            }
        }

        switch c {
        case "q" where recording != nil:
            return .done(Command(count: nil, action: .simple("q")))
        case "q", "@":
            guard index < keys.count else { return .incomplete }
            guard case .char(let name) = keys[index], name == "@" && c == "@" || name.isASCII && name.isLetter || (c == "@" && (name == "+" || name == "*")) else { return .invalid }
            return .done(Command(count: count, action: .simple("\(c)\(name)")))
        case "x", "X", "s", "S", "D", "C", "Y", "J", "o", "O", "a", "A", "i", "I", "p", "P", "u", "~", "v", "V", ":", "/", "?", ".":
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

    static let surroundTargets = "\"'`()b[]r{}B<>at"

    /// A surround replacement: one character, or a tag typed up to its ">"
    /// ("<em>", or after t: "em>").
    private func parseReplacement(_ keys: [VimKey], _ index: inout Int) -> ReplacementParse {
        guard index < keys.count else { return .incomplete }
        guard case .char(let c) = keys[index] else { return .invalid }
        index += 1
        if c == "<" || c == "t" {
            // The tag ends at ">" or Return; Backspace takes back a letter.
            var tag = "<"
            while index < keys.count {
                let key = keys[index]
                index += 1
                switch key {
                case .char(let k):
                    tag.append(k)
                    if k == ">" { return tag.count > 2 ? .done(tag) : .invalid }
                case .enter:
                    return tag.count > 1 ? .done(tag + ">") : .invalid
                case .backspace:
                    guard tag.count > 1 else { return .invalid }
                    tag.removeLast()
                default:
                    return .invalid
                }
            }
            return .incomplete
        }
        // Letters other than the aliases b, B, r and a mean nothing.
        if c.isLetter, !"bBra".contains(c) { return .invalid }
        return .done(String(c))
    }

    private enum ReplacementParse {
        case incomplete, invalid
        case done(String)

        func map(_ command: (String) -> Command) -> Parse {
            switch self {
            case .incomplete: .incomplete
            case .invalid: .invalid
            case .done(let replacement): .done(command(replacement))
            }
        }
    }

    private enum MotionParse {
        case incomplete, invalid
        case done(Motion)
    }

    private func parseMotion(_ keys: [VimKey], _ index: inout Int, textObjects: Bool = false) -> MotionParse {
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
        case "i" where textObjects, "a" where textObjects:
            guard index < keys.count else { return .incomplete }
            guard case .char(let kind) = keys[index], "wWpt\"'`()b[]{}B<>".contains(kind) else { return .invalid }
            index += 1
            return .done(.textObject(inner: c == "i", kind))
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
        activeRegister = command.register
        defer { activeRegister = nil }
        let wasVisual = inVisual
        failed = false
        let effect = perform(command)
        // Remember a change for "." (a repeat records itself again, count and all, as in vim);
        // changes made in visual mode are not repeated.
        // A change that failed (ci" with no quotes) leaves the last one in place;
        // one that worked counts even when the text came out the same.
        if !wasVisual, Self.isChange(command), !failed {
            let change = (command.count, (command.register.map { [VimKey.char("\""), .char($0)] } ?? []) + command.keys)
            if mode == .insert { changeInProgress = change } else { lastChange = change }
        }
        return effect
    }

    private static func isChange(_ command: Command) -> Bool {
        switch command.action {
        case .motion: false
        case .deleteSurround, .changeSurround, .addSurround: true
        case .operate(let op, _): op != .yank
        case .simple(let name):
            ["x", "X", "s", "S", "D", "C", "J", "o", "O", "i", "I", "a", "A", "p", "P", "~"].contains(name)
                || (name.hasPrefix("line") && name != "liney") || (name.hasPrefix("r") && name.count == 2)
        }
    }

    private mutating func perform(_ command: Command) -> VimEffect? {
        switch command.action {
        case .deleteSurround(let target):
            surround(target, count: command.count ?? 1, with: nil)
            return nil
        case .changeSurround(let target, let replacement):
            if let pair = Self.surroundPair(replacement) { surround(target, count: command.count ?? 1, with: pair) }
            return nil
        case .addSurround(let motion, let replacement):
            guard let pair = Self.surroundPair(replacement) else { return nil }
            surroundPair = pair
            if inVisual, let range = selection {
                let linewise = mode == .visualLine
                let (first, last) = (lineIndex(min(anchor, cursor)), lineIndex(max(anchor, cursor)))
                mode = .normal
                if linewise { wrapLines(first, last, in: pair, indenting: true) } else { wrap(range, in: pair) }
            } else if let motion {
                operate(.surround, motion: Self.resolved(motion, count: command.count), count: command.count ?? 1)
            } else {
                // yss: the line, without its indentation; a count takes more lines.
                let start = firstNonBlank(lineStart(cursor))
                let last = min(lineIndex(cursor) + (command.count ?? 1) - 1, lineStarts.count - 1)
                wrap(start..<lineEnd(lineStarts[last]), in: pair, trimming: true)
            }
            return nil
        case .motion(.textObject(let inner, let kind)):
            // In visual mode a text object selects its range.
            guard inVisual, let (range, linewise) = textObject(inner: inner, kind, count: command.count ?? 1), !range.isEmpty else {
                failed = true
                return nil
            }
            if linewise {
                anchor = lineStarts[range.lowerBound]
                cursor = lineStarts[range.upperBound - 1]
                mode = .visualLine
            } else {
                anchor = range.lowerBound
                cursor = range.upperBound - 1
            }
            return nil
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
        guard let target = target(of: motion, count: count, forOperator: false) else {
            failed = true
            return false
        }
        let before = cursor
        cursor = target.position
        switch motion {
        case .up, .down: break
        case .lineEnd: wantedColumn = .max
        default: wantedColumn = nil
        }
        clampCursor()
        // h at the start of a line, l at its end, w at the end of the text and
        // b at its start go nowhere; vim counts that as an error, which stops a macro.
        switch motion {
        case .left, .right, .wordForward, .wordBackward:
            if cursor == before {
                failed = true
                return false
            }
        default: break
        }
        return true
    }

    private mutating func runSimple(_ name: String, count: Int?) -> VimEffect? {
        let n = count ?? 1
        if inVisual {
            switch name {
            case "escape": mode = .normal
            case "q": if playDepth == 0 { stopRecording() }
            case "o": swap(&anchor, &cursor)
            case "J":
                let (low, high) = (min(anchor, cursor), max(anchor, cursor))
                mode = .normal
                cursor = low
                join(count: max(lineIndex(high) - lineIndex(low) + 1, 2))
            case "v", "V":
                let wanted: VimMode = name == "v" ? .visual : .visualLine
                mode = mode == wanted ? .normal : wanted
            case "p", "P":
                replaceSelection()
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
        case "i", "a", "A", "I": insertCount = min(n, 10_000)
            enterInsert(at: name == "i" ? cursor : name == "a" ? min(cursor + (lineIsEmpty(cursor) ? 0 : 1), lineEnd(cursor)) : name == "A" ? lineEnd(cursor) : firstNonBlank(lineStart(cursor)))
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
        case ".": repeatLastChange(count: count)
        case "q":
            // vim: "The 'q' command is disabled while executing a register".
            if playDepth == 0 { stopRecording() }
        case "ZZ": return .finish
        case "ZQ": return .cancel
        default:
            if name.hasPrefix("line"), let op = name.last.flatMap(Operator.init(rawValue:)) {
                runLine(op, count: n)
            } else if name.hasPrefix("q"), name.count == 2, let register = name.last {
                guard playDepth == 0 else { return nil }
                recording = register
                recordedKeys = []
            } else if name.hasPrefix("@"), name.count == 2, let register = name.last {
                play(register == "@" ? lastMacro : register, count: n)
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
        case .textObject:
            return nil
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
        if case .textObject(let inner, let kind) = motion {
            guard let (range, linewise) = textObject(inner: inner, kind, count: count) else {
                failed = true
                return
            }
            if linewise {
                guard !range.isEmpty else { return }
                applyLines(op, range.lowerBound, range.upperBound - 1)
            } else if op == .indent || op == .outdent {
                applyLines(op, lineIndex(range.lowerBound), lineIndex(max(range.upperBound - 1, range.lowerBound)))
            } else if !range.isEmpty || op == .change {
                apply(op, to: range)
            }
            return
        }
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
        guard let target = target(of: motion, count: count, forOperator: true) else {
            failed = true
            return
        }
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
        guard count == 1 || line + 1 < lineStarts.count else {
            failed = true
            return
        }
        let last = min(line + count - 1, lineStarts.count - 1)
        applyLines(op, line, last)
    }

    /// An operator on whole lines, `first` through `last`.
    private mutating func applyLines(_ op: Operator, _ first: Int, _ last: Int) {
        if op == .surround { return wrapLines(first, last, in: surroundPair, indenting: false) }
        let starts = lineStarts
        let start = starts[first]
        let bodyEnd = lineEnd(starts[last])
        let taken = String(text[start..<bodyEnd]) + "\n"
        switch op {
        case .yank:
            store(VimRegister(text: taken, linewise: true), yank: op == .yank)
            // yy and yj leave the cursor; yk takes it up to the first line.
            if lineIndex(cursor) != first { cursor = start + min(cursor - lineStart(cursor), max(bodyEnd - start, 0)) }
        case .delete:
            store(VimRegister(text: taken, linewise: true), yank: op == .yank)
            checkpoint(at: start)
            if last + 1 < starts.count {
                text.removeSubrange(start..<starts[last + 1])
            } else {
                // The last line takes the line break before it.
                text.removeSubrange(max(start - 1, 0)..<text.count)
            }
            cursor = firstNonBlank(lineStarts[min(first, lineStarts.count - 1)])
        case .change:
            store(VimRegister(text: taken, linewise: true), yank: op == .yank)
            checkpoint(at: start)
            // cc keeps one line, emptied but for its indentation.
            let indent = Array(text[start..<firstNonBlank(start)])
            text.replaceSubrange(start..<bodyEnd, with: indent)
            cursor = start + indent.count
            beginInsert()
            return
        case .surround:
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
        if op == .surround { return wrap(range, in: surroundPair, trimming: true) }
        let taken = String(text[range])
        switch op {
        case .yank:
            store(VimRegister(text: taken, linewise: false), yank: true)
            cursor = range.lowerBound
        case .delete, .change:
            // C on an empty line takes nothing, and keeps what was taken before.
            if !range.isEmpty { store(VimRegister(text: taken, linewise: false), yank: false) }
            checkpoint(at: range.lowerBound)
            text.removeSubrange(range)
            cursor = range.lowerBound
            if op == .change {
                beginInsert()
                return
            }
        case .surround:
            return
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
        insertBaseline = text
    }

    private mutating func join(count: Int) {
        let line = lineIndex(cursor)
        guard line + 1 < lineStarts.count else {
            failed = true
            return
        }
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
        let register = fetch()
        guard !register.text.isEmpty else {
            message = "E353: Nothing in register"
            failed = true
            return
        }
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
        guard cursor + count <= end else {
            failed = true
            return
        }
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
        guard end > cursor else {
            failed = true
            return
        }
        checkpoint()
        for i in cursor..<end {
            let c = text[i]
            let swapped = c.isUppercase ? c.lowercased() : c.uppercased()
            if swapped.count == 1 { text[i] = Character(swapped) }
        }
        cursor = min(end, max(lineEnd(cursor) - 1, lineStart(cursor)))
    }

    // MARK: - Text objects

    /// The range a text object covers: characters, or for whole lines
    /// (ip, ap, i{ around lines) the line numbers.
    private func textObject(inner: Bool, _ kind: Character, count: Int) -> (Range<Int>, Bool)? {
        switch kind {
        case "w", "W": return wordObject(inner: inner, big: kind == "W", count: count).map { ($0, false) }
        case "\"", "'", "`": return quoteObject(inner: inner, quote: kind).map { ($0, false) }
        case "(", ")", "b": return bracketObject(inner: inner, open: "(", close: ")", count: count)
        case "[", "]": return bracketObject(inner: inner, open: "[", close: "]", count: count)
        case "{", "}", "B": return bracketObject(inner: inner, open: "{", close: "}", count: count)
        case "<", ">": return bracketObject(inner: inner, open: "<", close: ">", count: count)
        case "p": return paragraphObject(inner: inner, count: count).map { ($0, true) }
        case "t": return tagObject(inner: inner, count: count).map { ($0, false) }
        default: return nil
        }
    }

    /// iw is the run of word, punctuation or blank characters under the
    /// cursor; aw adds the blanks after it (or before, at a line's end).
    private func wordObject(inner: Bool, big: Bool, count: Int) -> Range<Int>? {
        let n = text.count
        // On an empty line iw is nothing, so ciw still types there.
        guard cursor < n, text[cursor] != "\n" else { return inner ? cursor..<cursor : nil }
        func kind(_ i: Int) -> Int { text[i] == "\n" ? 3 : characterClass(i, big: big) }
        func runEnd(from i: Int) -> Int {
            var end = i
            while end + 1 < n, kind(end + 1) == kind(i) { end += 1 }
            return end
        }
        var start = cursor
        while start > 0, kind(start - 1) == kind(cursor) { start -= 1 }
        var end = runEnd(from: cursor)
        if inner {
            // A count past the words on the line fails, as in vim.
            for _ in 1..<max(count, 1) {
                guard end + 1 < n, kind(end + 1) != 3 else { return nil }
                end = runEnd(from: end + 1)
            }
            return start..<end + 1
        }
        for index in 0..<max(count, 1) {
            if index > 0 {
                guard end + 1 < n, kind(end + 1) != 3 else { return nil }
                end = runEnd(from: end + 1)
            }
            if kind(end) == 0 {
                // On blanks: they and the word after them.
                if end + 1 < n, kind(end + 1) != 3 { end = runEnd(from: end + 1) }
            } else if end + 1 < n, kind(end + 1) == 0 {
                end = runEnd(from: end + 1)
            } else if index == 0 {
                // No blanks after the word: take the ones before it instead.
                while start > 0, kind(start - 1) == 0 { start -= 1 }
            }
        }
        return start..<end + 1
    }

    /// i" is between the quotes around the cursor on its line (or the next
    /// quoted text after it); a" takes the quotes and the blanks after them.
    private func quoteObject(inner: Bool, quote: Character) -> Range<Int>? {
        let start = lineStart(cursor), end = lineEnd(cursor)
        guard let (open, close) = quotePair(quote) else { return nil }
        if inner { return (open + 1)..<close }
        var high = close + 1
        while high < end, text[high] == " " || text[high] == "\t" { high += 1 }
        var low = open
        if high == close + 1 { while low > start, text[low - 1] == " " || text[low - 1] == "\t" { low -= 1 } }
        return low..<high
    }

    /// The quotes around the cursor on its line, or the next quoted text after it.
    private func quotePair(_ quote: Character) -> (Int, Int)? {
        let start = lineStart(cursor), end = lineEnd(cursor)
        // A quote after an odd number of backslashes is escaped.
        let quotes = (start..<end).filter { i in
            text[i] == quote && (text[start..<i].reversed().prefix { $0 == "\\" }.count % 2 == 0)
        }
        var pair: (Int, Int)?
        if let at = quotes.firstIndex(of: cursor) {
            // On a quote, counting from the line's start says whether it opens or closes.
            pair = at % 2 == 0 ? (at + 1 < quotes.count ? (quotes[at], quotes[at + 1]) : nil) : (quotes[at - 1], quotes[at])
        } else if let before = quotes.last(where: { $0 < cursor }), let after = quotes.first(where: { $0 > cursor }) {
            pair = (before, after)
        } else if let after = quotes.firstIndex(where: { $0 > cursor }), after + 1 < quotes.count {
            // Before the first quote: the first quoted text on the line.
            pair = (quotes[after], quotes[after + 1])
        }
        return pair
    }

    /// i( is inside the brackets around the cursor; a( takes the brackets
    /// too. A count reaches further out. When the brackets sit on their own
    /// lines, i( is the lines between them.
    private func bracketObject(inner: Bool, open: Character, close: Character, count: Int) -> (Range<Int>, Bool)? {
        // On an opening bracket, that pair; anywhere else (a closing one
        // included) the nearest open bracket before the cursor that encloses it.
        var openAt = cursor < text.count && text[cursor] == open ? cursor : enclosingOpen(open, close, before: cursor)
        // Not inside a pair: the next pair after the cursor, as vim and Neovim do.
        if openAt == nil, count <= 1 { openAt = (cursor..<text.count).first { text[$0] == open } }
        for _ in 1..<max(count, 1) {
            guard let current = openAt else { break }
            openAt = enclosingOpen(open, close, before: current)
        }
        guard let start = openAt, let end = matchingClose(open, close, from: start) else { return nil }
        if !inner { return (start..<end + 1, false) }
        let breakAfterOpen = start + 1 < text.count && text[start + 1] == "\n"
        let closeInIndent = isInIndent(end) && lineIndex(end) > lineIndex(start)
        if breakAfterOpen, closeInIndent {
            let first = lineIndex(start) + 1, last = lineIndex(end) - 1
            // Nothing between: ci( types on the line of the ")".
            guard first <= last else { return (start + 2..<start + 2, false) }
            return (first..<last + 1, true)
        }
        // vim's two rules, each on its own: skip the line break after "(",
        // and stop before the line break above a ")" in the indentation.
        let low = breakAfterOpen ? start + 2 : start + 1
        let high = closeInIndent ? lineStart(end) - 1 : end
        return (low..<max(low, high), false)
    }

    private func enclosingOpen(_ open: Character, _ close: Character, before position: Int) -> Int? {
        var depth = 0
        var i = position - 1
        while i >= 0 {
            if text[i] == close { depth += 1 } else if text[i] == open {
                if depth == 0 { return i }
                depth -= 1
            }
            i -= 1
        }
        return nil
    }

    private func matchingClose(_ open: Character, _ close: Character, from start: Int) -> Int? {
        var depth = 0
        for i in start..<text.count {
            if text[i] == open { depth += 1 } else if text[i] == close {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }

    /// it is between the tags around the cursor (<a>…</a>); at takes the
    /// tags too. A count reaches further out. Self-closing tags are skipped.
    private func tagObject(inner: Bool, count: Int) -> Range<Int>? {
        guard !text.isEmpty else { return nil }
        var found = 0
        var i = min(cursor, text.count - 1)
        // The cursor may be inside a tag; start from that tag's "<".
        if let open = (0...i).last(where: { text[$0] == "<" }), !text[open..<i].contains(">") { i = open }
        while i >= 0 {
            if let tag = openingTag(at: i), let close = closingTag(tag.name, from: tag.end + 1), close.end >= cursor {
                found += 1
                if found == max(count, 1) { return inner ? (tag.end + 1)..<close.start : i..<(close.end + 1) }
            }
            i -= 1
        }
        return nil
    }

    /// The tag starting at `start` if it is an opening tag: its name and where its ">" is.
    private func openingTag(at start: Int) -> (name: String, end: Int)? {
        guard text[start] == "<", start + 1 < text.count, text[start + 1].isLetter else { return nil }
        var j = start + 1
        while j < text.count, text[j].isLetter || text[j].isNumber || "-:_.".contains(text[j]) { j += 1 }
        // The tag ends at the first ">" outside a quoted attribute value.
        var end = j
        var quote: Character?
        while end < text.count {
            let c = text[end]
            if let open = quote { if c == open { quote = nil } } else if c == "\"" || c == "'" { quote = c } else if c == ">" { break }
            end += 1
        }
        guard end < text.count, text[end - 1] != "/" else { return nil }
        return (String(text[(start + 1)..<j]), end)
    }

    /// The "</name>" that closes a tag opened before `from`, skipping nested ones of the same name.
    private func closingTag(_ name: String, from: Int) -> (start: Int, end: Int)? {
        let closing = Array("</" + name)
        var depth = 0
        var i = from
        while i < text.count {
            if text[i] == "<" {
                if i + closing.count < text.count, Array(text[i..<(i + closing.count)]) == closing, text[i + closing.count] == ">" || text[i + closing.count].isWhitespace {
                    guard depth > 0 else { return (i, (i..<text.count).first { text[$0] == ">" } ?? i) }
                    depth -= 1
                } else if let tag = openingTag(at: i), tag.name == name {
                    depth += 1
                }
            }
            i += 1
        }
        return nil
    }

    /// ip is the block of lines, blank or not, the cursor is in; ap adds the
    /// blank lines after it (or before, at the end of the text).
    private func paragraphObject(inner: Bool, count: Int) -> Range<Int>? {
        let starts = lineStarts
        func blank(_ line: Int) -> Bool {
            text[starts[line]..<(line + 1 < starts.count ? starts[line + 1] - 1 : text.count)].allSatisfy { $0 == " " || $0 == "\t" }
        }
        func blockEnd(from line: Int) -> Int {
            var end = line
            while end + 1 < starts.count, blank(end + 1) == blank(line) { end += 1 }
            return end
        }
        let line = lineIndex(cursor)
        var first = line
        while first > 0, blank(first - 1) == blank(line) { first -= 1 }
        var last = blockEnd(from: line)
        let blocks = inner ? max(count, 1) : max(count, 1) * 2
        for _ in 1..<blocks {
            guard last + 1 < starts.count else { break }
            last = blockEnd(from: last + 1)
        }
        if !inner, !blank(line), blank(last) == false, first > 0 {
            // No blank lines after the paragraph: take the ones before it.
            while first > 0, blank(first - 1) { first -= 1 }
        }
        return first..<last + 1
    }

    // MARK: - Surround

    /// What a surround replacement puts around the text. ( [ { add a space
    /// inside, ) ] } and their aliases b r B don't; < or t takes a tag.
    static func surroundPair(_ replacement: String) -> (open: String, close: String)? {
        if replacement.hasPrefix("<") {
            let name = replacement.dropFirst().prefix { !$0.isWhitespace && $0 != ">" }
            return name.isEmpty ? nil : (replacement, "</\(name)>")
        }
        switch replacement {
        case ")", "b": return ("(", ")")
        case "(": return ("( ", " )")
        case "]", "r": return ("[", "]")
        case "[": return ("[ ", " ]")
        case "}", "B": return ("{", "}")
        case "{": return ("{ ", " }")
        case ">", "a": return ("<", ">")
        default: return (replacement, replacement)
        }
    }

    /// Where the surrounding marks are: quotes on the line, brackets around
    /// the cursor (a count reaches further out), or a tag pair.
    private func surroundParts(_ target: Character, count: Int) -> (open: Range<Int>, close: Range<Int>)? {
        let aliases: [Character: Character] = ["b": ")", "B": "}", "r": "]", "a": ">"]
        let target = aliases[target] ?? target
        switch target {
        case "\"", "'", "`":
            guard let (open, close) = quotePair(target) else { return nil }
            return (open..<open + 1, close..<close + 1)
        case "t":
            guard let outer = tagObject(inner: false, count: count), let inner = tagObject(inner: true, count: count) else { return nil }
            return (outer.lowerBound..<inner.lowerBound, inner.upperBound..<outer.upperBound)
        default:
            let pairs: [Character: (Character, Character)] = ["(": ("(", ")"), ")": ("(", ")"), "[": ("[", "]"), "]": ("[", "]"), "{": ("{", "}"), "}": ("{", "}"), "<": ("<", ">"), ">": ("<", ">")]
            guard let (open, close) = pairs[target], let (range, _) = bracketObject(inner: false, open: open, close: close, count: count) else { return nil }
            return (range.lowerBound..<range.lowerBound + 1, range.upperBound - 1..<range.upperBound)
        }
    }

    /// ds (no replacement) and cs. An opening bracket as the target also
    /// takes the blanks just inside the pair.
    private mutating func surround(_ target: Character, count: Int, with replacement: (open: String, close: String)?) {
        guard var (open, close) = surroundParts(target, count: count) else {
            failed = true
            return
        }
        if "([{<".contains(target) {
            var inner = open.upperBound
            while inner < close.lowerBound, text[inner] == " " || text[inner] == "\t" { inner += 1 }
            var end = close.lowerBound
            while end > inner, text[end - 1] == " " || text[end - 1] == "\t" { end -= 1 }
            (open, close) = (open.lowerBound..<inner, end..<close.upperBound)
        }
        checkpoint(at: open.lowerBound)
        text.replaceSubrange(close, with: Array(replacement?.close ?? ""))
        text.replaceSubrange(open, with: Array(replacement?.open ?? ""))
        cursor = open.lowerBound
        clampCursor()
    }

    /// ys and visual S on characters: the pair goes around `range`, less
    /// any blanks at its end when `trimming` (ysw leaves the space outside).
    private mutating func wrap(_ range: Range<Int>, in pair: (open: String, close: String), trimming: Bool = false) {
        var end = range.upperBound
        if trimming { while end > range.lowerBound, text[end - 1] == " " || text[end - 1] == "\t" { end -= 1 } }
        checkpoint(at: range.lowerBound)
        text.insert(contentsOf: Array(pair.close), at: end)
        text.insert(contentsOf: Array(pair.open), at: range.lowerBound)
        cursor = range.lowerBound
        wantedColumn = nil
        clampCursor()
    }

    /// ys over lines and linewise visual S: the pair goes on lines of its own.
    /// Visual S also indents the lines between one level; ys leaves them.
    private mutating func wrapLines(_ first: Int, _ last: Int, in pair: (open: String, close: String), indenting: Bool) {
        let starts = lineStarts
        let start = starts[first]
        let bodyEnd = lineEnd(starts[last])
        let indent = String(text[start..<firstNonBlank(start)])
        let block = String(text[start..<bodyEnd])
        let inner = indenting ? TextTransforms.indent(block) : block
        let open = pair.open.trimmingCharacters(in: .whitespaces), close = pair.close.trimmingCharacters(in: .whitespaces)
        checkpoint(at: start)
        text.replaceSubrange(start..<bodyEnd, with: Array(indent + open + "\n" + inner + "\n" + indent + close))
        cursor = start
        wantedColumn = nil
        clampCursor()
    }

    // MARK: - Macros

    private mutating func stopRecording() {
        guard let name = recording else { return }
        if !recordedKeys.isEmpty { recordedKeys.removeLast() } // the q that stopped it
        let text = String(recordedKeys.map(Self.character(for:)))
        let lower = Character(name.lowercased())
        let old = name.isUppercase ? registers[lower]?.text ?? "" : ""
        registers[lower] = VimRegister(text: old + text, linewise: false)
        recording = nil
        recordedKeys = []
    }

    /// Plays register `name` as keys, `count` times. Keys queue up rather
    /// than nest, so a recursive macro (qa…@aq) runs as long as it needs.
    /// It stops at the first command that fails, as vim does, and after
    /// `macroKeyLimit` keys in all.
    private mutating func play(_ name: Character?, count: Int) {
        guard let name else { failed = true; return }
        let source: String? = name == "+" || name == "*" ? clipboard.read() : registers[Character(name.lowercased())]?.text
        guard let source, !source.isEmpty else { failed = true; return }
        lastMacro = name
        let keys = source.map(Self.key(for:))
        // More than the limit can never play, so a huge count needs no more keys than that.
        let copies = min(count, Self.macroKeyLimit / keys.count + 1)
        macroQueue += Array(Array(repeating: keys, count: copies).joined().reversed())
        guard playDepth == 0 else { return }
        playDepth = 1
        macroBudget = Self.macroKeyLimit
        // One undo takes back the whole macro, as in vim.
        let undoBase = undoStack.count, trimmedBefore = undoTrimmed
        defer {
            playDepth = 0
            macroQueue = []
            pending = []
            let first = undoBase - (undoTrimmed - trimmedBefore)
            if first >= 0, undoStack.count > first + 1 { undoStack.removeSubrange((first + 1)...) }
            // Typing in the window after a macro that ended in insert mode is the person's, not the macro's.
            if mode == .insert { insertBaseline = text }
        }
        while let key = macroQueue.popLast() {
            guard macroBudget > 0 else {
                message = "Macro stopped after \(Self.macroKeyLimit) keys"
                failed = true
                return
            }
            macroBudget -= 1
            failed = false
            if let effect = handle(key), effect == .finish || effect == .cancel {
                // A macro can't close the window.
                message = "Macro stopped: it would have closed the window"
                return
            }
            if failed {
                if mode == .insert { leaveInsert() }
                return
            }
        }
    }

    /// Keys as a register holds them: Esc, Return and ⌃ keys as control characters.
    static func character(for key: VimKey) -> Character {
        switch key {
        case .char(let c): c
        case .ctrl(let c): Character(UnicodeScalar((c.asciiValue ?? 64) & 0x1f))
        case .escape: "\u{1b}"
        case .enter: "\r"
        case .backspace: "\u{8}"
        case .left: "\u{F702}"
        case .right: "\u{F703}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        }
    }

    static func key(for character: Character) -> VimKey {
        switch character {
        case "\u{1b}": .escape
        case "\r": .enter
        case "\u{8}": .backspace
        case "\u{F702}": .left
        case "\u{F703}": .right
        case "\u{F700}": .up
        case "\u{F701}": .down
        default:
            if let value = character.asciiValue, value < 0x20, character != "\n", character != "\t" {
                .ctrl(Character(UnicodeScalar(value | 0x60)))
            } else {
                .char(character)
            }
        }
    }

    // MARK: - Repeat

    /// Runs the last change again; a count replaces the one it had.
    private mutating func repeatLastChange(count: Int?) {
        guard let change = lastChange else { return }
        let digits = (count ?? change.count).map { VimKey.keys(String($0)) } ?? []
        isRepeating = true
        defer { isRepeating = false }
        // A change that fails part way stops, so its typed keys don't run as commands.
        for key in digits + change.keys {
            failed = false
            _ = handle(key)
            if failed {
                if mode == .insert { leaveInsert() }
                return
            }
        }
    }

    // MARK: - Registers

    /// Puts taken text in the unnamed register and the one named, as vim
    /// does: a yank also goes in "0, "A to "Z add to "a to "z, "_ keeps
    /// nothing, and "+ or "* is the system clipboard.
    private mutating func store(_ taken: VimRegister, yank: Bool) {
        guard activeRegister != "_" else { return }
        register = taken
        if yank, activeRegister == nil {
            registers["0"] = taken
            if usesSystemClipboard { clipboard.write(taken.text) }
        }
        switch activeRegister {
        case "+"?, "*"?: clipboard.write(taken.text)
        case let name? where name.isUppercase:
            let lower = Character(name.lowercased())
            if let old = registers[lower], old.linewise || taken.linewise {
                // Lines and characters together make lines, each part on its own.
                func asLines(_ part: VimRegister) -> String { part.linewise || part.text.hasSuffix("\n") ? part.text : part.text + "\n" }
                registers[lower] = VimRegister(text: asLines(old) + asLines(taken), linewise: true)
            } else {
                registers[lower] = VimRegister(text: (registers[lower]?.text ?? "") + taken.text, linewise: false)
            }
            register = registers[lower]!
        case let name? where name.isLetter:
            registers[name] = taken
        default:
            break
        }
    }

    /// The register a put reads: the one named, or the unnamed one.
    private func fetch() -> VimRegister {
        switch activeRegister {
        case "+"?, "*"?:
            let text = (clipboard.read() ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            return VimRegister(text: text, linewise: text.hasSuffix("\n"))
        case "_"?: return VimRegister(text: "", linewise: false)
        case let name?: return name == "\"" ? register : registers[Character(name.lowercased())] ?? VimRegister(text: "", linewise: false)
        case nil:
            guard usesSystemClipboard else { return register }
            // The clipboard, whoever put it there; a final line break makes it lines, as vim's "+ does.
            let text = (clipboard.read() ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            return VimRegister(text: text, linewise: text.hasSuffix("\n"))
        }
    }

    /// p or P in visual mode: the selection is replaced by the register,
    /// and what was selected goes in the unnamed register.
    private mutating func replaceSelection() {
        guard let range = selection else { return }
        let replacement = fetch()
        // Nothing to put (an empty clipboard, or a picture on it): the selection stays, as in vim.
        guard !replacement.text.isEmpty else {
            message = "E353: Nothing in register"
            failed = true
            return
        }
        let linewise = mode == .visualLine
        let (first, last) = (lineIndex(min(anchor, cursor)), lineIndex(max(anchor, cursor)))
        mode = .normal
        let named = activeRegister
        activeRegister = nil
        let lines = Array(replacement.linewise ? replacement.text : replacement.text + "\n")
        if linewise {
            let wasFinal = last == lineStarts.count - 1
            applyLines(.delete, first, last)
            if wasFinal, first == 0 {
                text = Array(lines.dropLast())
                cursor = firstNonBlank(0)
            } else if wasFinal {
                let at = text.count
                text.insert(contentsOf: ["\n"] + lines.dropLast(), at: at)
                cursor = firstNonBlank(at + 1)
            } else {
                let at = lineStarts[first]
                text.insert(contentsOf: lines, at: at)
                cursor = firstNonBlank(at)
            }
        } else {
            apply(.delete, to: range)
            let pasted = replacement.linewise ? ["\n"] + lines : Array(replacement.text)
            text.insert(contentsOf: pasted, at: range.lowerBound)
            cursor = replacement.linewise ? firstNonBlank(range.lowerBound + 1) : range.lowerBound + pasted.count - 1
        }
        activeRegister = named
        clampCursor()
    }

    // MARK: - Undo

    /// Saves the text for undo. `position` is where the change begins,
    /// where undo leaves the cursor, as vim does.
    private mutating func checkpoint(at position: Int? = nil) {
        undoStack.append((string, position ?? cursor))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
            undoTrimmed += 1
        }
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
