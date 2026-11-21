import Foundation

/// A key as the vim keymap sees it.
enum VimKey: Equatable, Sendable {
    case char(Character)
    case ctrl(Character)
    /// ⌥ with a letter, by key code ("j", "k"): the Edit window's line moves.
    case alt(Character)
    /// ⌘⇧R ("R"): smartparens' raise, s-R in David's Doom.
    case command(Character)
    case escape, enter, backspace
    case left, right, up, down

    /// "dw" → [d, w], for tests and for replaying keys.
    static func keys(_ text: String) -> [VimKey] { text.map(VimKey.char) }
}

enum VimMode: Equatable, Sendable {
    case normal, insert, visual, visualLine
    /// ⌃V: a rectangle of columns over several lines (ROADMAP C12).
    case visualBlock
    /// `R`: typing replaces the characters under the cursor (ROADMAP C12).
    case replace
    /// Typing after ":", "/" or "?".
    case commandLine
}

/// What the window does after a key.
enum VimEffect: Equatable, Sendable {
    case finish, cancel
    /// `:set wrap` (true), `:set nowrap` (false), `:set wrap!` or `:set invwrap` (nil: toggle).
    case wrap(Bool?)
    /// `:set number` / `nu` (true), `nonumber` / `nonu` (false), `number!` / `nu!` /
    /// `invnumber` / `invnu` (nil: toggle).
    case number(Bool?)
    /// The same for `relativenumber` / `rnu`.
    case relativeNumber(Bool?)
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
    /// A visual block's rows, one a line, pasted as a block (ROADMAP C12).
    var blockwise = false
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
    /// Why the last command did nothing, where vim would beep ("d3j: no line below"). The
    /// window shows it until the next key; vim's behavior is unchanged and nothing sounds.
    private(set) var failureHint: String?
    /// The keys of the command being run, as typed, for the hint.
    private var typed: [VimKey] = []
    /// A change command (c…) that couldn't run: keys are dropped until Esc.
    private(set) var ignoresTyping = false

    /// Whether `keys` (after a count and register) start a change: c, the one whose text
    /// would have gone into insert mode.
    static func isChange(_ keys: [VimKey]) -> Bool {
        var index = 0
        _ = readCount(keys, &index)
        if index + 1 < keys.count, keys[index] == .char("\"") { index += 2; _ = readCount(keys, &index) }
        return index < keys.count && keys[index] == .char("c")
    }
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
    /// The last snipe (s, f, t, z, x and their backward forms), for ; , and the repeat keys.
    private var lastSnipe: (keys: [Character], forward: Bool, inclusive: Bool, count: Int, key: Character)?
    /// Right after a snipe, its own key repeats it and its backward key goes back, for one key
    /// (evil-snipe-repeat-keys, set-transient-map).
    private var snipeRepeatKeys: (forward: Character, backward: Character)?
    private var lastSearch: (pattern: String, forward: Bool, wholeWord: Bool)?
    /// Marks a-z and A-Z (separate, as in evil), as character places (ROADMAP C37). They
    /// move with the text as evil's markers do: `marksText` is the text they were last placed
    /// on, and a change is found by what stayed the same at either end.
    private var marks: [Character: Int] = [:]
    private var marksText: [Character] = []
    /// What `R` replaced, newest last (nil: a character added past the line's end), for
    /// Backspace; the keys typed, for the count and `.`.
    private var replaced: [Character?] = []
    private var replaceKeys: [VimKey] = []
    private var replaceCount = 1
    /// After `I`, `A` or `c` on a visual block: the other lines get what is typed on the
    /// first, at `column` (nil: each line's end); `pad` fills short lines with spaces.
    private var blockInsert: (lines: ClosedRange<Int>, column: Int?, pad: Bool, cornerLine: Int, cornerColumn: Int)?
    /// The last visual selection, for `gv`.
    private var lastVisual: (mode: VimMode, anchor: Int, cursor: Int)?
    /// The last `:s`, for `&` and a bare `:s`.
    private var lastSubstitute: VimSubstitute.Command?
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
    /// No lines at all, as vim's empty buffer: an empty text, or dd on the last line. One
    /// empty line is different (dd on it still yanks it); both are "" here.
    private var noLines: Bool
    /// Keys a macro may play in all, recursion included.
    static let macroKeyLimit = 100_000

    /// The largest count; 999999, as typed, times another 999999 stays far from overflow.
    static let maxCount = 999_999
    /// Changes undo remembers, as vim's default 'undolevels'.
    static let undoLimit = 1000

    init(_ text: String) {
        self.text = Array(text)
        original = self.text
        noLines = text.isEmpty
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

    /// The visual block's piece of each line, top to bottom; nil outside ⌃V.
    var blockSelection: [Range<Int>]? {
        guard mode == .visualBlock else { return nil }
        let block = block()
        return (block.first...block.last).map { line in
            let start = lineStarts[line], length = lineEnd(start) - start
            let low = start + min(block.left, length)
            let high = block.toEnd ? start + length : start + min(block.right + 1, length)
            return low..<max(low, high)
        }
    }

    /// The block's lines and columns (characters, not screen columns), and whether it runs
    /// to each line's end ($).
    private func block() -> (first: Int, last: Int, left: Int, right: Int, toEnd: Bool) {
        let anchorLine = lineIndex(anchor), cursorLine = lineIndex(cursor)
        let anchorColumn = anchor - lineStart(anchor), cursorColumn = cursor - lineStart(cursor)
        return (min(anchorLine, cursorLine), max(anchorLine, cursorLine), min(anchorColumn, cursorColumn), max(anchorColumn, cursorColumn), wantedColumn == .max)
    }

    // MARK: - Keys

    /// Handles one key. Returns `.finish` or `.cancel` when the window should close.
    mutating func handle(_ key: VimKey) -> VimEffect? {
        message = nil
        moveMarks()
        if playDepth == 0, !isRepeating { failureHint = nil }
        if recording != nil, playDepth == 0, !isRepeating { recordedKeys.append(key) }
        switch mode {
        case .insert: handleInsert(key); return nil
        case .commandLine: return handleCommandLine(key)
        case .replace: handleReplace(key); return nil
        case .normal, .visual, .visualLine, .visualBlock:
            // Right after a snipe its own key repeats it, its backward key goes back (evil-snipe).
            let repeatKeys = snipeRepeatKeys
            snipeRepeatKeys = nil
            if pending.isEmpty, let repeatKeys, case .char(let c) = key, c == repeatKeys.forward || c == repeatKeys.backward {
                pending = [.char(c == repeatKeys.forward ? ";" : ",")]
                if case .done(let command) = parse(pending) {
                    if playDepth == 0, !isRepeating { typed = [key] }
                    pending = []
                    return run(command)
                }
                pending = []
            }
            if pending.isEmpty, let arrow = arrowMotion(key) {
                _ = runMotion(arrow, count: 1)
                return nil
            }
            if ignoresTyping {
                // After a change command that didn't run, typing is dropped until Esc, so
                // the text meant for insert mode never runs as commands.
                if key == .escape || key == .ctrl("[") || key == .ctrl("c") { ignoresTyping = false } else if playDepth == 0, !isRepeating {
                    failureHint = "typing ignored until Esc"
                }
                return nil
            }
            pending.append(key)
            switch parse(pending) {
            case .incomplete: return nil
            case .invalid:
                if playDepth == 0, !isRepeating { failureHint = "\(Self.describe(pending)): not a command" }
                ignoresTyping = Self.isChange(pending)
                pending = []
                failed = true
                return nil
            case .done(let command) where { if case .simple(let name) = command.action { name.hasPrefix("unbuilt:") } else { false } }():
                if case .simple(let name) = command.action, playDepth == 0, !isRepeating {
                    failureHint = "\(Self.describe(pending)): \(name.dropFirst("unbuilt:".count))"
                }
                pending = []
                failed = true
                return nil
            case .done(let command):
                if playDepth == 0, !isRepeating { typed = pending }
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
        case .visualBlock: "VISUAL BLOCK"
        case .commandLine: "NORMAL"
        case .replace: "REPLACE"
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
        // In insert mode ⌥ keys type their own characters (the window lets them through).
        case .alt, .command: break
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
        wantedColumn = nil
        if blockInsert != nil {
            finishBlockInsert(typed: String(typedSinceInsert(single: repeats)))
            clampCursor()
            return
        }
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
        case "set number", "set nu": return .number(true)
        case "set nonumber", "set nonu": return .number(false)
        case "set number!", "set nu!", "set invnumber", "set invnu": return .number(nil)
        case "set relativenumber", "set rnu": return .relativeNumber(true)
        case "set norelativenumber", "set nornu": return .relativeNumber(false)
        case "set relativenumber!", "set rnu!", "set invrelativenumber", "set invrnu": return .relativeNumber(nil)
        case "q!": return .cancel
        case "q":
            if isChanged {
                message = "E37: No write since last change (add ! to override)"
                failed = true
                return nil
            }
            return .cancel
        default:
            if let substitute = VimSubstitute.parse(command) {
                self.substitute(substitute)
                return nil
            }
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

    // MARK: - gq

    /// gq (ROADMAP C12 item 4): the lines `first`...`last` re-wrapped, paragraph by
    /// paragraph (blank lines between), to the text width: a paragraph's lines joined as J
    /// does, then broken at the last space that fits, the new lines taking its first line's
    /// indent. Width 79, as vim with textwidth=0; `VimTextWidth` changes it.
    private mutating func format(_ first: Int, _ last: Int) {
        let lines = string.components(separatedBy: "\n")
        let width = UserDefaults.standard.integer(forKey: "VimTextWidth") > 0 ? UserDefaults.standard.integer(forKey: "VimTextWidth") : 79
        let formatted = VimFormat.wrap(Array(lines[first...last]), width: width)
        let result = Array(lines[..<first]) + formatted + Array(lines[(last + 1)...])
        let joined = result.joined(separator: "\n")
        let lastLine = first + formatted.count - 1
        if joined != string {
            checkpoint()
            text = Array(joined)
        }
        cursor = firstNonBlank(lineStarts[min(lastLine, lineStarts.count - 1)])
        wantedColumn = nil
    }

    // MARK: - Comments

    /// The line comment for the text, which has no file type: Doom takes it from the major
    /// mode, so the mode is guessed (David, 2026-11-21). A line already commented decides;
    /// else text starting with "(" or ";" is Lisp (";;", as clojure-mode), SQL's first word
    /// gives "--", a " //" after code or lines ending in { } or ; give "//", and anything
    /// else "#".
    static func commentString(for text: String) -> String {
        let lines = text.split(separator: "\n").map { $0.drop { $0 == " " || $0 == "\t" } }.filter { !$0.isEmpty }
        for line in lines {
            if line.hasPrefix(";") { return ";;" }
            if line.hasPrefix("//") { return "//" }
            if line.hasPrefix("--") { return "--" }
            if line.hasPrefix("#") { return "#" }
        }
        guard let first = lines.first else { return "#" }
        if first.hasPrefix("(") { return ";;" }
        // A "//" after code, but not a URL's "://".
        if lines.contains(where: { $0.contains(" //") }) { return "//" }
        let word = first.prefix { $0.isLetter }.lowercased()
        if ["select", "with", "insert", "update", "delete", "create"].contains(word) { return "--" }
        if lines.contains(where: { line in line.trimmingCharacters(in: .whitespaces).last.map { "{};".contains($0) } ?? false }) { return "//" }
        return "#"
    }

    /// gc on lines `first`...`last`, as evil-nerd-commenter: blank lines are left alone; if
    /// every other line is commented they are uncommented (all the comment characters and one
    /// space after them go), else each gets the comment and a space at the lines' smallest
    /// indentation. One undo step; the cursor goes to the first line's first non-blank.
    private mutating func toggleComment(_ first: Int, _ last: Int) {
        let marker = Self.commentString(for: string)
        let markerCharacter = marker.first!
        var lines = string.components(separatedBy: "\n")
        let indices = (first...last).filter { !lines[$0].allSatisfy { $0 == " " || $0 == "\t" } }
        guard !indices.isEmpty else { return }
        func body(_ line: String) -> Substring { line.drop { $0 == " " || $0 == "\t" } }
        // ";" or "#" alone starts a comment; "//" and "--" need both characters.
        let start = marker == ";;" ? ";" : marker
        let commented = indices.allSatisfy { body(lines[$0]).hasPrefix(start) }
        if commented {
            for i in indices {
                let line = lines[i]
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                var rest = body(line).drop { $0 == markerCharacter }
                if rest.first == " " { rest = rest.dropFirst() }
                lines[i] = String(indent) + rest
            }
        } else {
            let column = indices.map { lines[$0].prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            for i in indices {
                let line = lines[i]
                lines[i] = String(line.prefix(column)) + marker + " " + line.dropFirst(column)
            }
        }
        checkpoint(at: lineStarts[first])
        text = Array(lines.joined(separator: "\n"))
        cursor = firstNonBlank(lineStarts[first])
        wantedColumn = nil
    }

    // MARK: - Re-indenting

    /// Lines `=` asked to re-indent, for the window: it runs the Text wheel's Re-indent
    /// formatter on the whole text and hands the result to `applyReindent`. Doom's = asks the
    /// major mode; Re-indent's formatter for the text (cljfmt for Clojure) indents as Doom's
    /// clojure-mode does, and `=` and Re-indent then agree (David, 2026-11-21).
    var reindentRequest: ClosedRange<Int>?

    /// The formatter's result for the text as it was (`original`): each line in `lines` takes
    /// the indentation the formatter gave the same line, keeping its own text, in one undo step.
    /// Lines are matched by their text with blanks ignored, in order, since a formatter may drop
    /// blank lines (cljfmt does) or tidy spaces inside a line; a line with no match keeps its
    /// indentation. The cursor goes to the first line's first non-blank. Nothing changes if the
    /// text changed meanwhile.
    mutating func applyReindent(_ formatted: String, lines: ClosedRange<Int>, original: String) {
        guard string == original else {
            message = "=: the text changed while formatting; nothing was re-indented"
            return
        }
        let old = original.components(separatedBy: "\n"), new = formatted.components(separatedBy: "\n")
        guard lines.upperBound < old.count else { return }
        func key(_ line: String) -> String { line.filter { !$0.isWhitespace } }
        // Each old line's matching new line, found in order.
        var match: [Int: Int] = [:]
        var j = 0
        for i in old.indices where !key(old[i]).isEmpty {
            guard let found = (j..<new.count).first(where: { key(new[$0]) == key(old[i]) }) else { continue }
            match[i] = found
            j = found + 1
        }
        var result = old
        for i in lines {
            let body = old[i].drop { $0 == " " || $0 == "\t" }
            if body.isEmpty {
                result[i] = ""
            } else if let k = match[i] {
                result[i] = String(new[k].prefix { $0 == " " || $0 == "\t" }) + body
            }
        }
        cursor = firstNonBlank(lineStarts[lines.lowerBound])
        let joined = result.joined(separator: "\n")
        guard joined != original else { return }
        checkpoint(at: cursor)
        text = Array(joined)
        cursor = firstNonBlank(lineStarts[lines.lowerBound])
        wantedColumn = nil
        clampCursor()
    }

    /// The window could not re-indent: no formatter for the text, or the formatter failed.
    mutating func reindentFailed(_ reason: String) {
        message = "=: \(reason)"
    }

    // MARK: - Exchanging

    /// The range the first gx marked, while the text is as it was then (evil-exchange keeps
    /// markers; here any change in between drops the mark).
    private var exchangeMark: (range: Range<Int>, linewise: Bool, text: [Character])?

    /// What the window highlights: the range gx marked, waiting for the second gx.
    var exchangeHighlight: Range<Int>? {
        guard let mark = exchangeMark, mark.text == text else { return nil }
        return mark.range
    }

    /// gx (evil-exchange): the first marks `range`; the second swaps the two texts in one undo
    /// step. The cursor goes to the start of the second range, moved by what changed before
    /// it, as in Doom; over lines to the first non-blank. Ranges that overlap are not swapped
    /// and the mark is dropped.
    private mutating func exchange(_ range: Range<Int>, linewise: Bool) {
        guard let mark = exchangeMark, mark.text == text else {
            exchangeMark = (range, linewise, text)
            return
        }
        exchangeMark = nil
        let (first, second) = mark.range.lowerBound <= range.lowerBound ? (mark.range, range) : (range, mark.range)
        guard !mark.range.overlaps(range) || mark.range.isEmpty || range.isEmpty, mark.range != range else {
            if mark.range != range { cursor = first.lowerBound }
            failed = true
            return
        }
        let firstText = Array(text[first]), secondText = Array(text[second])
        // The cursor goes to the start of the range this gx took, moved by the swap before it.
        let position = range.lowerBound
        checkpoint(at: first.lowerBound)
        text.replaceSubrange(second, with: firstText)
        text.replaceSubrange(first, with: secondText)
        let shift = secondText.count - firstText.count
        // Side by side, evil-exchange swaps its texts the other way round and point ends at the start.
        cursor = first.upperBound == second.lowerBound ? first.lowerBound : position >= first.upperBound ? position + shift : position
        if linewise || mark.linewise { cursor = firstNonBlank(lineStart(cursor)) }
        clampCursor()
    }

    // MARK: - Slurp, barf and raise

    /// The forms (smartparens' sexps) between `low` and `high`: a bracketed form, a "…"
    /// string or a word, with quote and reader prefixes (' ` ~ @ # ^) attached; blanks, commas
    /// and ; comments between them are skipped.
    private func forms(from low: Int, to high: Int, backward: Bool = false) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var i = low
        while i < high {
            // Every turn must move on; one that doesn't ends the forms rather than loop forever
            // (2026-11-21: a stray ")" spun here and froze the app).
            let turn = i
            defer { if i <= turn { i = high + 1 } }
            let c = text[i]
            if c.isWhitespace || c == "," { i += 1; continue }
            if c == ";" { while i < high, text[i] != "\n" { i += 1 }; continue }
            let start = i
            while i < high, "'`~@#^".contains(text[i]) { i += 1 }
            guard i < high else { result.append(start..<i); break }
            if "([{".contains(text[i]) {
                guard let end = matchingAnyClose(from: i), end < high else { return result }
                i = end + 1
            } else if text[i] == "\"" {
                i = min(skipLisp(i) ?? high, high)
            } else {
                // A word; \x is a character, whatever x is.
                while i < high, !text[i].isWhitespace, !"()[]{}\",;".contains(text[i]) { i += text[i] == "\\" ? 2 : 1 }
                i = min(i, high)
                // A stray closing bracket ends the forms reachable from before it, and the ones
                // before it can't be reached from after (2026-11-21: it looped forever).
                if i == start {
                    if !backward { return result }
                    result = []
                    i += 1
                    continue
                }
            }
            result.append(start..<i)
        }
        return result
    }

    /// Past a "…" string, a ; comment (to the line's end) or a \x character at `i`, for the
    /// bracket scanners; nil when none starts there.
    private func skipLisp(_ i: Int) -> Int? {
        switch text[i] {
        case "\\": return min(i + 2, text.count)
        case ";":
            var j = i
            while j < text.count, text[j] != "\n" { j += 1 }
            return j
        case "\"":
            var j = i + 1
            while j < text.count, text[j] != "\"" { j += text[j] == "\\" ? 2 : 1 }
            return min(j + 1, text.count)
        default: return nil
        }
    }

    /// The closing bracket for the bracket at `open`, any kind counting, strings skipped.
    private func matchingAnyClose(from open: Int) -> Int? {
        var depth = 0, i = open
        while i < text.count {
            let c = text[i]
            if i > open, let next = skipLisp(i) {
                guard next > i else { return nil }
                i = next
                continue
            } else if "([{".contains(c) {
                depth += 1
            } else if ")]}".contains(c) {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// The innermost pair around the cursor (Emacs's point, just before the cursor's character):
    /// a bracketed form, or with `strings` a "…" string.
    private func enclosingPair(strings: Bool) -> (open: Int, close: Int)? {
        if strings {
            var i = 0
            while i < text.count {
                if let next = skipLisp(i) {
                    if text[i] == "\"", next - 1 > i, text[next - 1] == "\"", i < cursor, cursor <= next - 1 { return (i, next - 1) }
                    i = max(next, i + 1)
                    continue
                }
                i += 1
            }
        }
        var best: (Int, Int)?
        var i = 0
        while i < cursor {
            if let next = skipLisp(i) {
                i = max(next, i + 1)
                continue
            }
            if "([{".contains(text[i]), let close = matchingAnyClose(from: i), close >= cursor { best = (i, close) }
            i += 1
        }
        return best
    }

    /// ⌃L ⌃H ⌃J ⌃K: smartparens' forward and backward slurp and barf on the innermost form (or
    /// string) around the cursor, `count` forms at a time. One undo step; the cursor stays with
    /// the text, kept inside the form. Lines are not re-indented (Doom's clojure-mode does).
    private mutating func slurpOrBarf(_ name: String, count: Int) {
        guard let pair = enclosingPair(strings: true) else {
            failed = true
            return
        }
        let openText = text[pair.open], closeText = text[pair.close]
        // The forms of the list around this one (or the whole text at the top).
        let parent = enclosingPairOf(pair.open)
        let parentLow = parent.map { $0.open + 1 } ?? 0, parentHigh = parent?.close ?? text.count
        var removeAt: Int, insertAt: Int, inserted: Character
        switch name {
        case "slurpForward":
            let after = forms(from: pair.close + 1, to: parentHigh)
            guard !after.isEmpty else { failed = true; return }
            (removeAt, insertAt, inserted) = (pair.close, after[min(count, after.count) - 1].upperBound, closeText)
        case "slurpBackward":
            let before = forms(from: parentLow, to: pair.open, backward: true)
            guard !before.isEmpty else { failed = true; return }
            (removeAt, insertAt, inserted) = (pair.open, before[max(before.count - count, 0)].lowerBound, openText)
        case "barfForward":
            let inside = forms(from: pair.open + 1, to: pair.close)
            guard !inside.isEmpty else { failed = true; return }
            let kept = inside.count - min(count, inside.count)
            (removeAt, insertAt, inserted) = (pair.close, kept > 0 ? inside[kept - 1].upperBound : pair.open + 1, closeText)
        default:
            let inside = forms(from: pair.open + 1, to: pair.close)
            guard !inside.isEmpty else { failed = true; return }
            let moved = min(count, inside.count)
            (removeAt, insertAt, inserted) = (pair.open, moved < inside.count ? inside[moved].lowerBound : pair.close, openText)
        }
        // Undo puts the cursor back where it was, as in Doom.
        checkpoint(at: cursor)
        // The cursor moves as Emacs's point does through a deletion and an insertion.
        var point = cursor
        text.remove(at: removeAt)
        if point > removeAt { point -= 1 }
        let at = insertAt > removeAt ? insertAt - 1 : insertAt
        text.insert(inserted, at: at)
        if point > at { point += 1 }
        // Kept inside the form, as smartparens leaves it.
        func moved(_ i: Int) -> Int {
            let j = i > removeAt ? i - 1 : i
            return j >= at ? j + 1 : j
        }
        let newOpen = removeAt == pair.open ? at : moved(pair.open)
        let newClose = removeAt == pair.close ? at : moved(pair.close)
        cursor = min(max(point, newOpen + 1), newClose)
        wantedColumn = nil
        clampCursor()
    }

    /// The bracketed form around position `i` (not counting a bracket at `i` itself).
    private func enclosingPairOf(_ i: Int) -> (open: Int, close: Int)? {
        var best: (Int, Int)?
        var j = 0
        while j < i {
            if let next = skipLisp(j) {
                j = max(next, j + 1)
                continue
            }
            if "([{".contains(text[j]), let close = matchingAnyClose(from: j), close > i { best = (j, close) }
            j += 1
        }
        return best
    }

    /// ⌘⇧R, smartparens' raise (s-R in David's Doom): the form at the cursor, or the next one
    /// in the list, takes the place of the list around it (a count raises that many forms from
    /// there); the cursor goes to its start. With too few forms the list stays and the cursor
    /// goes to its start.
    private mutating func raise(count: Int) {
        guard let list = enclosingPair(strings: false) else {
            failed = true
            return
        }
        let inside = forms(from: list.open + 1, to: list.close)
        guard let first = inside.firstIndex(where: { $0.contains(cursor) }) ?? inside.firstIndex(where: { $0.lowerBound >= cursor }),
              first + max(count, 1) - 1 < inside.count else {
            cursor = list.open
            failed = true
            return
        }
        let raised = Array(text[inside[first].lowerBound..<inside[first + max(count, 1) - 1].upperBound])
        checkpoint(at: list.open)
        text.replaceSubrange(list.open...list.close, with: raised)
        cursor = list.open
        wantedColumn = nil
        clampCursor()
    }

    // MARK: - Aligning

    /// The lines a motion or text object covers from the cursor, for gl.
    private mutating func lineRange(of motion: Motion, count: Int) -> (Int, Int)? {
        if case .textObject(let inner, let kind) = motion {
            if kind == "w" || kind == "W" {
                let word = wordObject(inner: inner, big: kind == "W", count: count)
                return word.found ? (lineIndex(word.start), lineIndex(word.end)) : nil
            }
            guard let (range, linewise) = textObject(inner: inner, kind, count: count) else { return nil }
            return linewise ? (range.lowerBound, range.upperBound - 1) : (lineIndex(range.lowerBound), lineIndex(max(range.upperBound - 1, range.lowerBound)))
        }
        guard let target = target(of: motion, count: count, forOperator: true) else { return nil }
        let low = min(cursor, target.position), high = max(cursor, target.position)
        var last = lineIndex(high)
        if target.kind == .exclusive, high == lineStart(high), last > lineIndex(low) { last -= 1 }
        return (lineIndex(low), last)
    }

    /// gl / gL (evil-lion, ROADMAP C28) on lines `first`...`last`: runs of two or more spaces
    /// before (gl) or after (gL) each match become one, then each match, column by column,
    /// gets spaces before it (gl) or after it (gL) so they line up, as Emacs's align-region
    /// with spacing 0. `firstOnly` (a count of 1) does the first match on each line only. The
    /// pattern is the character typed, or after "/" a pattern typed to Return. The cursor stays.
    private mutating func align(_ first: Int, _ last: Int, right: Bool, pattern: String, firstOnly: Bool) {
        let source = pattern.count > 1 && pattern.hasPrefix("/") ? String(pattern.dropFirst()) : NSRegularExpression.escapedPattern(for: pattern)
        guard let regex = try? NSRegularExpression(pattern: source) else {
            failed = true
            return
        }
        func matches(_ line: String) -> [Range<Int>] {
            let found = regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { Range($0.range, in: line) }
                .filter { !$0.isEmpty }
                .map { line.distance(from: line.startIndex, to: $0.lowerBound)..<line.distance(from: line.startIndex, to: $0.upperBound) }
            return firstOnly ? Array(found.prefix(1)) : found
        }
        var lines = string.components(separatedBy: "\n")
        let line = lineIndex(cursor), column = cursor - lineStart(cursor)
        // Squeeze the spaces next to each match.
        for i in first...last {
            var characters = Array(lines[i])
            for match in matches(lines[i]).reversed() {
                if right {
                    var end = match.upperBound
                    while end < characters.count, characters[end] == " " { end += 1 }
                    if end - match.upperBound >= 2 { characters.replaceSubrange(match.upperBound..<end, with: [" "]) }
                } else {
                    var start = match.lowerBound
                    while start > 0, characters[start - 1] == " " { start -= 1 }
                    if match.lowerBound - start >= 2 { characters.replaceSubrange(start..<match.lowerBound, with: [" "]) }
                }
            }
            lines[i] = String(characters)
        }
        // Line up the k-th matches, k = 1, 2, …
        var k = 0
        while true {
            let columns = (first...last).compactMap { i -> (Int, Int)? in
                let found = matches(lines[i])
                guard k < found.count else { return nil }
                return (i, right ? found[k].upperBound : found[k].lowerBound)
            }
            guard !columns.isEmpty else { break }
            let target = columns.map(\.1).max()!
            for (i, at) in columns where at < target {
                var characters = Array(lines[i])
                characters.insert(contentsOf: Array(repeating: " ", count: target - at), at: at)
                lines[i] = String(characters)
            }
            k += 1
        }
        let joined = lines.joined(separator: "\n")
        guard joined != string else { return }
        checkpoint(at: lineStarts[first])
        text = Array(joined)
        let start = lineStarts[min(line, lineStarts.count - 1)]
        cursor = start + min(column, max(lineEnd(start) - start - 1, 0))
        wantedColumn = nil
    }

    // MARK: - Moving lines

    /// ⌥J / ⌥K (David's Doom config, ~/.doom.d/config.el my/move-line-*): the cursor's line,
    /// or every line a visual selection touches, swaps places with the `count` lines below or
    /// above, in one undo step. The cursor stays on the moved line at its column; a selection
    /// is selected again in visual line mode, so the keys can be pressed again. Past the first
    /// or last line nothing moves.
    private mutating func moveLines(down: Bool, count: Int) {
        let visual = inVisual
        let first = lineIndex(visual ? min(anchor, cursor) : cursor)
        let last = lineIndex(visual ? max(anchor, cursor) : cursor)
        var lines = string.components(separatedBy: "\n")
        guard down ? last + count < lines.count : first - count >= 0 else {
            failed = true
            return
        }
        let column = cursor - lineStart(cursor)
        let cursorAtBottom = !visual || lineIndex(cursor) == last
        let block = Array(lines[first...last])
        lines.removeSubrange(first...last)
        let target = down ? first + count : first - count
        lines.insert(contentsOf: block, at: target)
        checkpoint()
        text = Array(lines.joined(separator: "\n"))
        let newFirst = target, newLast = target + block.count - 1
        func position(_ line: Int) -> Int {
            let start = lineStarts[line]
            return start + min(column, max(lineEnd(start) - start - 1, 0))
        }
        if visual {
            mode = .visualLine
            anchor = lineStarts[cursorAtBottom ? newFirst : newLast]
            cursor = position(cursorAtBottom ? newLast : newFirst)
        } else {
            cursor = position(newFirst)
        }
    }

    // MARK: - Visual block

    /// Where the cursor goes after a block change: the block's top-left.
    private func blockCorner() -> Int {
        let block = block()
        let start = lineStarts[block.first]
        return start + min(block.left, lineEnd(start) - start)
    }

    /// d, x, y, c, ~, u, U and > < on a visual block (ROADMAP C12 item 3).
    private mutating func applyBlock(_ op: Operator) {
        let block = block()
        let ranges = blockSelection ?? []
        let corner = blockCorner()
        let rows = ranges.map { String(text[$0]) }
        switch op {
        case .yank:
            store(VimRegister(text: rows.joined(separator: "\n"), linewise: false, blockwise: true), yank: true)
            mode = .normal
            cursor = corner
        case .delete, .change:
            store(VimRegister(text: rows.joined(separator: "\n"), linewise: false, blockwise: true), yank: false)
            checkpoint()
            for range in ranges.reversed() { text.removeSubrange(range) }
            mode = .normal
            cursor = corner
            if op == .change {
                blockInsert = (block.first...block.last, block.left, false, block.first, block.left)
                beginInsert()
            }
        case .upper, .lower, .toggleCase:
            checkpoint()
            for range in ranges.reversed() { text.replaceSubrange(range, with: Array(transformed(String(text[range]), op))) }
            mode = .normal
            cursor = corner
        case .indent, .outdent, .surround, .format, .comment, .reindent:
            mode = .normal
            applyLines(op, block.first, block.last)
        case .exchange:
            // evil-exchange swaps blocks with blocks only; not built here.
            mode = .normal
            cursor = corner
            failed = true
        }
    }

    /// I or A on a visual block: insert mode on the first line; the other lines get the same
    /// text when it ends.
    private mutating func startBlockInsert(append: Bool) {
        let block = block()
        let firstStart = lineStarts[block.first]
        let firstLength = lineEnd(firstStart) - firstStart
        let column: Int? = append ? (block.toEnd ? nil : block.right + 1) : block.left
        let position = firstStart + min(column ?? firstLength, firstLength)
        blockInsert = (block.first...block.last, column, append, block.first, block.left)
        mode = .normal
        enterInsert(at: position)
        // A past the first line's end pads it too.
        if append, let column, firstLength < column {
            let padding = Array(repeating: Character(" "), count: column - firstLength)
            text.insert(contentsOf: padding, at: lineEnd(firstStart))
            cursor = lineEnd(firstStart)
            // The padding isn't typed text, so it isn't copied to the other lines.
            insertBaseline = text
        }
    }

    /// Copies the text typed on the block's first line to its other lines, as vim does on Esc.
    private mutating func finishBlockInsert(typed: String) {
        guard let insert = blockInsert else { return }
        blockInsert = nil
        if !typed.isEmpty, !typed.contains("\n") {
            for line in insert.lines.dropFirst().reversed() where line < lineStarts.count {
                let start = lineStarts[line], length = lineEnd(start) - start
                if let column = insert.column {
                    if length < column {
                        // I and c leave lines that don't reach the block alone; A pads them.
                        guard insert.pad else { continue }
                        text.insert(contentsOf: Array(repeating: Character(" "), count: column - length) + Array(typed), at: start + length)
                    } else {
                        text.insert(contentsOf: Array(typed), at: start + column)
                    }
                } else {
                    text.insert(contentsOf: Array(typed), at: start + length)
                }
            }
        }
        let start = lineStarts[min(insert.cornerLine, lineStarts.count - 1)]
        cursor = start + min(insert.cornerColumn, max(lineEnd(start) - start, 0))
    }

    // MARK: - Replace mode

    /// `R` (ROADMAP C12): each character typed replaces the one under the cursor, or is
    /// added past the line's end; Backspace puts the original back (before where `R`
    /// began it only moves left); Esc ends it, typing it count-1 more times, as vim does.
    private mutating func handleReplace(_ key: VimKey) {
        switch key {
        case .char(let character):
            replaceKeys.append(key)
            put(character)
        case .backspace:
            guard cursor > lineStart(cursor) else { return }
            if let original = replaced.popLast() {
                cursor -= 1
                if let original { text[cursor] = original } else { text.remove(at: cursor) }
                replaceKeys.append(key)
            } else {
                cursor -= 1
            }
        case .escape, .ctrl("["), .ctrl("c"):
            let typed = replaceKeys.compactMap { if case .char(let c) = $0 { c } else { nil } }
            if replaceKeys.allSatisfy({ if case .char = $0 { true } else { false } }) {
                for _ in 1..<max(replaceCount, 1) { typed.forEach { put($0) } }
            }
            if !isRepeating { lastChange = (replaceCount > 1 ? replaceCount : nil, [.char("R")] + replaceKeys + [.escape]) }
            if string == undoStack.last?.text { undoStack.removeLast() }
            mode = .normal
            if cursor > lineStart(cursor) { cursor -= 1 }
            clampCursor()
        default:
            break
        }
    }

    private mutating func put(_ character: Character) {
        if cursor < lineEnd(cursor) {
            replaced.append(text[cursor])
            text[cursor] = character
        } else {
            replaced.append(nil)
            text.insert(character, at: cursor)
        }
        cursor += 1
    }

    // MARK: - ⌃A and ⌃X

    /// ⌃A and ⌃X (ROADMAP C12 item 5): add `amount` to the first number on the line at or
    /// after the cursor, as vim with nrformats=bin,hex does. A "-" right before the digits
    /// is its sign; leading zeros keep the width; hex keeps its letters' case. The cursor
    /// goes to the number's last character. No number: nothing happens (vim beeps).
    private mutating func addToNumber(_ amount: Int) {
        let start = lineStart(cursor), end = lineEnd(cursor)
        let line = String(text[start..<end])
        guard let (range, replacement) = VimNumber.add(amount, in: line, at: cursor - start) else {
            failed = true
            return
        }
        checkpoint()
        let replaced = Array(replacement)
        text.replaceSubrange((start + range.lowerBound)..<(start + range.upperBound), with: replaced)
        cursor = start + range.lowerBound + replaced.count - 1
        wantedColumn = nil
    }

    /// ⌃A / ⌃X and g⌃A / g⌃X in visual mode (evil-numbers, ROADMAP C29): every number that
    /// starts in the selection gets `amount`, or with `eachMore` the k-th gets k × `amount`.
    /// One undo step; the cursor goes to the selection's start in normal mode.
    private mutating func addToNumbersInSelection(_ amount: Int, eachMore: Bool) {
        let starts = lineStarts
        // Each line's piece of the selection, as columns.
        var pieces: [(line: Int, columns: Range<Int>)] = []
        if let rows = blockSelection {
            for row in rows { pieces.append((lineIndex(row.lowerBound), (row.lowerBound - lineStart(row.lowerBound))..<(row.upperBound - lineStart(row.lowerBound)))) }
        } else if let range = selection {
            for line in lineIndex(range.lowerBound)...lineIndex(max(range.upperBound - 1, range.lowerBound)) {
                let start = starts[line], end = lineEnd(start)
                let low = max(range.lowerBound, start) - start, high = min(range.upperBound, end) - start
                pieces.append((line, low..<max(low, high)))
            }
        }
        let corner = mode == .visualBlock ? blockCorner() : (selection?.lowerBound ?? cursor)
        mode = .normal
        let regex = try! NSRegularExpression(pattern: "0[xX][0-9a-fA-F]+|0[bB][01]+|-?[0-9]+")
        var changes: [(range: Range<Int>, text: String)] = []
        var k = 0
        for piece in pieces {
            // Only the selected part is read, so a number cut by the selection's edge counts
            // from there, as evil-numbers does (1|23 v⌃A makes 133).
            let start = starts[piece.line] + piece.columns.lowerBound
            let part = String(text[start..<(starts[piece.line] + piece.columns.upperBound)])
            for match in regex.matches(in: part, range: NSRange(part.startIndex..., in: part)) {
                guard let found = Range(match.range, in: part) else { continue }
                let lower = part.distance(from: part.startIndex, to: found.lowerBound)
                let upper = part.distance(from: part.startIndex, to: found.upperBound)
                k += 1
                let step = eachMore ? amount.multipliedReportingOverflow(by: k).partialValue : amount
                changes.append(((start + lower)..<(start + upper), VimNumber.changed(String(part[found]), by: step)))
            }
        }
        cursor = corner
        guard !changes.isEmpty else {
            failed = true
            clampCursor()
            return
        }
        checkpoint(at: corner)
        for change in changes.reversed() { text.replaceSubrange(change.range, with: Array(change.text)) }
        clampCursor()
    }

    // MARK: - Substitute

    /// Runs `:s` (ROADMAP C12): each line of the range has its first match (every match with
    /// `g`) replaced, in one undo step; the cursor goes to the last line changed. An empty
    /// pattern is the last one searched for; a bare `:s` repeats the last replacement.
    private mutating func substitute(_ given: VimSubstitute.Command) {
        var command = given
        if command.pattern.isEmpty {
            // A bare :s repeats the last substitute's pattern; :s//x/ uses the last search, as in vim.
            let bare = given.replacement == "~"
            guard let last = bare ? (lastSubstitute?.pattern ?? lastSearch?.pattern) : (lastSearch?.pattern ?? lastSubstitute?.pattern) else {
                message = "E35: No previous regular expression"
                failed = true
                return
            }
            command.pattern = last
        }
        if command.replacement == "~", given.pattern.isEmpty { command.replacement = lastSubstitute?.replacement ?? "" }
        let (icu, caseOverride) = VimSubstitute.icuPattern(command.pattern)
        let ignoreCase = caseOverride ?? command.ignoreCase ?? !command.pattern.contains(where: \.isUppercase)
        guard let regex = try? NSRegularExpression(pattern: icu, options: ignoreCase ? [.caseInsensitive] : []) else {
            message = "E486: Pattern not found: \(command.pattern)"
            failed = true
            return
        }
        let lines = string.components(separatedBy: "\n")
        let current = lineIndex(cursor)
        func resolve(_ bound: VimSubstitute.Bound) -> Int {
            switch bound {
            case .number(let n): min(max(n, 1), lines.count) - 1
            case .current: current
            case .last: lines.count - 1
            }
        }
        let range: ClosedRange<Int>
        switch command.range {
        case .current: range = current...current
        case .all: range = 0...(lines.count - 1)
        case .lines(let a, let b): range = min(resolve(a), resolve(b))...max(resolve(a), resolve(b))
        case .visual:
            // '<,'> is the last visual selection, typed or filled in.
            let lines = lastVisual.map { (lineIndex(min($0.anchor, $0.cursor, text.count)), lineIndex(min(max($0.anchor, $0.cursor), text.count))) } ?? (current, current)
            range = lines.0...lines.1
        }
        let template = VimSubstitute.template(command.replacement)
        var out: [String] = []
        var substitutions = 0
        var changedLines = 0
        var lastChanged: Int?
        for (index, line) in lines.enumerated() {
            guard range.contains(index) else {
                out.append(line)
                continue
            }
            let whole = NSRange(line.startIndex..., in: line)
            let matches = command.global ? regex.matches(in: line, range: whole) : regex.firstMatch(in: line, range: whole).map { [$0] } ?? []
            guard !matches.isEmpty else {
                out.append(line)
                continue
            }
            var changed = line as NSString
            for match in matches.reversed() {
                let replacement = regex.replacementString(for: match, in: line, offset: 0, template: template)
                changed = changed.replacingCharacters(in: match.range, with: replacement) as NSString
            }
            substitutions += matches.count
            changedLines += 1
            // A replacement with line breaks makes more than one line.
            let pieces = (changed as String).components(separatedBy: "\n")
            out += pieces
            lastChanged = out.count - 1
        }
        lastSearch = (command.pattern, true, false)
        lastSubstitute = command
        guard let lastChanged else {
            message = "E486: Pattern not found: \(command.pattern)"
            failed = true
            return
        }
        checkpoint()
        text = Array(out.joined(separator: "\n"))
        cursor = firstNonBlank(lineStarts[min(lastChanged, lineStarts.count - 1)])
        wantedColumn = nil
        if changedLines > 2 { message = "\(substitutions) substitutions on \(changedLines) lines" }
    }

    // MARK: - Parsing

    enum Motion: Equatable {
        case left, right, up, down
        case wordForward(big: Bool), wordBackward(big: Bool), wordEnd(big: Bool)
        case lineStart, firstNonBlank, lineEnd
        /// G (nil: the last line) and gg (nil: the first).
        case goToLine(Int?)
        /// evil-snipe (David's Doom, ROADMAP C26): s / S (2 characters), f / F / t / T (1), and
        /// after an operator z / Z / x / X. `key` is the command's forward key, for repeating.
        case snipe([Character], forward: Bool, inclusive: Bool, key: Character)
        /// ; and , (and the snipe's own key again): the last snipe, over the whole text.
        case repeatFind(reverse: Bool)
        case matchingBracket
        case paragraphForward, paragraphBackward
        case searchNext(reverse: Bool)
        case searchWord(forward: Bool)
        /// 'a (the mark's line, linewise) and `a (its exact place), ROADMAP C37.
        case mark(Character, exact: Bool)
        /// iw, a", i(, ap…: a range around the cursor, after an operator or in visual mode.
        case textObject(inner: Bool, Character)
    }

    enum Operator: Character {
        case delete = "d", change = "c", yank = "y", indent = ">", outdent = "<"
        case upper = "U", lower = "u", toggleCase = "~"
        /// ys: wraps the range in `surroundPair`.
        case surround = "S"
        /// gq: re-wraps lines to the text width (ROADMAP C12).
        case format = "q"
        /// gc: comments or uncomments lines, as evil-nerd-commenter (ROADMAP C25).
        case comment = "C"
        /// gx: marks a range, and the next gx swaps the two (evil-exchange, ROADMAP C27).
        case exchange = "X"
        /// =: re-indents lines with the Text wheel's Re-indent formatter (ROADMAP C34).
        case reindent = "="
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
        /// evil-lion: gl / gL (right: true) align lines on a character or a typed pattern.
        case align(right: Bool, Motion?, String, firstOnly: Bool)
    }

    private enum Parse {
        case incomplete, invalid
        case done(Command)
    }

    private var inVisual: Bool { mode == .visual || mode == .visualLine || mode == .visualBlock }

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
        if let unbuilt = unbuiltCommand(keys, from: index) {
            guard let reason = unbuilt else { return .incomplete }
            return .done(Command(count: nil, action: .simple("unbuilt:" + reason)))
        }
        let result = parseCommand(keys, from: index, count: count)
        guard case .done(var command) = result else { return result }
        command.register = register
        // The keys "." runs again, without counts: it puts the total back in front.
        command.keys = keys.indices.filter { $0 >= body && !(command.innerCount?.contains($0) ?? false) }.map { keys[$0] }
        return .done(command)
    }

    /// vim commands this engine doesn't have, read to their end so the keys after them
    /// never run as commands of their own (2026-11-20: `=ip` and `ma` fell into insert
    /// mode). nil: not one of them; .some(nil): wait for more keys; .some(reason): done.
    static let unbuiltOperators = ["!", "g?", "gw", "g@", "zf"]
    static let unbuiltWithArgument: [String: String] = [
        "z": "not built", "[": "not built", "]": "not built",
    ]
    static let unbuiltAlone = ["gJ", "gp", "gP", "gi", "g;", "g,", "ga", "g+", "gd", "gD", "g*", "g#", "g&"]

    private func unbuiltCommand(_ keys: [VimKey], from start: Int) -> String?? {
        var typed = ""
        for key in keys[start...] {
            guard case .char(let c) = key else { break }
            typed.append(c)
        }
        guard let first = typed.first else { return nil }
        // "g" or "z" alone waits for its next key; "g⌃A" (a ⌃ key next) is left to the parser.
        if typed == "g" || typed == "z", keys.count > start + typed.count { return nil }
        if typed == "g" || typed == "z" && !inVisual { return .some(nil) }
        if Self.unbuiltAlone.contains(where: { typed.hasPrefix($0) }), !inVisual || typed.hasPrefix("gJ") {
            return .some("not built")
        }
        for (prefix, reason) in Self.unbuiltWithArgument where !inVisual && typed.hasPrefix(prefix) {
            // "gg", "gv", "gu" and the other built g commands are not "g'" and are left alone.
            if prefix == "z", typed.count > 1, typed.hasPrefix("zf") { break }
            guard typed.count > prefix.count else { return .some(nil) }
            return .some(reason)
        }
        guard let op = Self.unbuiltOperators.first(where: { typed.hasPrefix($0) }) else {
            // A "g" or "z" second key that is neither built nor listed is left to the parser.
            _ = first
            return nil
        }
        if inVisual { return .some("not built") }
        var index = start + op.count
        _ = Self.readCount(keys, &index)
        guard index < keys.count else { return .some(nil) }
        // ==, !!, g??, gcc, gww: the line form.
        if keys[index] == .char(op.last!) { return .some("not built") }
        var motionIndex = index
        switch parseMotion(keys, &motionIndex, textObjects: true) {
        case .incomplete: return .some(nil)
        case .done, .invalid: return .some("not built")
        }
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

        // ⌥J / ⌥K (and ⌥↓ / ⌥↑): move the line, or the selected lines, as David's Doom config does.
        if case .alt(let c) = key, c == "j" || c == "k" {
            return .done(Command(count: count, action: .simple(c == "j" ? "moveDown" : "moveUp")))
        }
        if key == .command("R") { return .done(Command(count: count, action: .simple("raise"))) }
        if case .ctrl(let c) = key {
            switch c {
            case "r": return .done(Command(count: count, action: .simple("redo")))
            case "[", "c": return .done(Command(count: nil, action: .simple("escape")))
            case "v": return .done(Command(count: nil, action: .simple("block")))
            case "a" where !inVisual: return .done(Command(count: count, action: .simple("increment")))
            // In visual mode, evil-numbers: every number in the selection.
            case "a" where inVisual, "x" where inVisual: return .done(Command(count: count, action: .simple(c == "a" ? "visualIncrement" : "visualDecrement")))
            case "x" where !inVisual: return .done(Command(count: count, action: .simple("decrement")))
            // Slurp and barf, as David's Doom binds smartparens (~/.doom.d/config.el:821-824).
            case "l", "h", "j", "k": return .done(Command(count: count, action: .simple(["l": "slurpForward", "h": "slurpBackward", "j": "barfForward", "k": "barfBackward"][c]!)))
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
            // ⌃F as a target is embrace's "(name …)" form, kept as \u{6}.
            let target: Character
            if keys[index] == .ctrl("f") { target = "\u{6}" } else {
                guard case .char(let typed) = keys[index], Self.surroundTargets.contains(typed) else { return .invalid }
                target = typed
            }
            index += 1
            if c == "d" { return .done(Command(count: count, action: .deleteSurround(target))) }
            return parseReplacement(keys, &index).map { Command(count: count, action: .changeSurround(target, $0)) }
        }

        // evil-lion: gl{motion}{char} and gL; in visual mode gl{char}. "/" reads a pattern to Return.
        if c == "g", index < keys.count, keys[index] == .char("l") || keys[index] == .char("L") {
            let right = keys[index] == .char("L")
            index += 1
            var motion: Motion?
            // The count before gl is evil-lion's (1: the first match only); one after it is the motion's.
            let outerCount = count
            var motionCount: Int?
            if !inVisual {
                motionCount = readCount()
                switch parseMotion(keys, &index, textObjects: true) {
                case .incomplete: return .incomplete
                case .invalid: return .invalid
                case .done(let parsed): motion = parsed
                }
            }
            guard index < keys.count else { return .incomplete }
            guard case .char(let target) = keys[index] else { return .invalid }
            index += 1
            var pattern = String(target)
            if target == "/" {
                pattern = ""
                while true {
                    guard index < keys.count else { return .incomplete }
                    let key = keys[index]
                    index += 1
                    if key == .enter { break }
                    if key == .backspace { if !pattern.isEmpty { pattern.removeLast() }; continue }
                    guard case .char(let k) = key else { return .invalid }
                    pattern.append(k)
                }
                pattern = "/" + (pattern.isEmpty ? "/" : pattern)
            }
            // evil-lion: "Only COUNT `1' is supported at the moment".
            if let outerCount, outerCount > 1 { return .done(Command(count: nil, action: .simple("unbuilt:only a count of 1 works before gl"))) }
            return .done(Command(count: motionCount, action: .align(right: right, motion, pattern, firstOnly: outerCount == 1)))
        }

        // An operator: d, c, y, >, <, g~, gu, gU (or the same in visual mode).
        var op: Operator?
        if let simpleOp = Operator(rawValue: c), [.delete, .change, .yank, .indent, .outdent, .reindent].contains(simpleOp) {
            op = simpleOp
        } else if c == "g" {
            guard let second = next() else { return .incomplete }
            if case .char("v") = second, !inVisual {
                index += 1
                return .done(Command(count: nil, action: .simple("gv")))
            }
            // gn / gN in normal mode select the next (last) search match.
            if case .char(let kind) = second, kind == "n" || kind == "N", !inVisual {
                index += 1
                return .done(Command(count: count, action: .simple(kind == "n" ? "gn" : "gN")))
            }
            // Doom's evil-numbers keys (doom+/modules/editor/evil/config.el:567-571): g= and g- add
            // and take one, as ⌃A and ⌃X; in visual mode they count up, and g+ adds one to each.
            if case .char(let g) = second, g == "=" || g == "-" || (g == "+" && inVisual) {
                index += 1
                let name = inVisual ? (g == "=" ? "visualIncrementEach" : g == "-" ? "visualDecrementEach" : "visualIncrement") : (g == "=" ? "increment" : "decrement")
                return .done(Command(count: count, action: .simple(name)))
            }
            // g⌃A / g⌃X in visual mode: numbers that count up, one step more each (evil-numbers).
            if inVisual, second == .ctrl("a") || second == .ctrl("x") {
                index += 1
                return .done(Command(count: count, action: .simple(second == .ctrl("a") ? "visualIncrementEach" : "visualDecrementEach")))
            }
            if case .char(let g) = second, ["~", "u", "U", "q"].contains(g) {
                index += 1
                op = Operator(rawValue: g)
            } else if case .char("c") = second {
                index += 1
                op = .comment
            } else if case .char("x") = second {
                index += 1
                op = .exchange
            } else if case .char("X") = second, !inVisual {
                index += 1
                return .done(Command(count: nil, action: .simple("exchangeCancel")))
            }
        }
        if let op {
            if inVisual { return .done(Command(count: count, action: .operate(op, nil))) }
            let countStart = index
            let motionCount = readCount()
            let innerCount = countStart..<index
            let total = count.map { min($0 * (motionCount ?? 1), Self.maxCount) } ?? motionCount
            guard let doubled = next() else { return .incomplete }
            // dd, cc, yy, >>, <<, g~~, guu, gUU, gqq, and gugu-style repeats. gUgg is gU to the first line.
            var repeated = false
            if case .char(let d) = doubled, d == op.rawValue || (op == .comment && d == "c") || (op == .exchange && d == "x") {
                repeated = true
            } else if case .char("g") = doubled, [.toggleCase, .lower, .upper, .format].contains(op) {
                guard index + 1 < keys.count else { return .incomplete }
                if case .char(op.rawValue) = keys[index + 1] {
                    index += 2
                    repeated = true
                }
            }
            if repeated {
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
            case "~": return .done(Command(count: count, action: .operate(.toggleCase, nil)))
            case "u": return .done(Command(count: count, action: .operate(.lower, nil)))
            case "U": return .done(Command(count: count, action: .operate(.upper, nil)))
            case "o", "v", "V", "J", "p", "P", ":": return .done(Command(count: count, action: .simple(String(c))))
            case "I", "A", "O" where mode == .visualBlock: return .done(Command(count: count, action: .simple("block\(c)")))
            case "r" where mode == .visualBlock:
                guard case .char(let target)? = next() else { return next() == nil ? .incomplete : .invalid }
                return .done(Command(count: nil, action: .simple("blockr\(target)")))
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
        case "x", "X", "D", "C", "Y", "J", "o", "O", "a", "A", "i", "I", "p", "P", "u", "~", "v", "V", ":", "/", "?", ".", "&", "R":
            return .done(Command(count: count, action: .simple(String(c))))
        case "r":
            guard case .char(let target)? = next() else { return next() == nil ? .incomplete : .invalid }
            return .done(Command(count: count, action: .simple("r\(target)")))
        case "m":
            guard case .char(let name)? = next() else { return next() == nil ? .incomplete : .invalid }
            guard name.isASCII, name.isLetter else { return .invalid }
            return .done(Command(count: nil, action: .simple("mark\(name)")))
        case "Z":
            guard case .char(let second)? = next() else { return next() == nil ? .incomplete : .invalid }
            return ["Z", "Q"].contains(second) ? .done(Command(count: nil, action: .simple("Z\(second)"))) : .invalid
        default:
            return .invalid
        }
    }

    static let surroundTargets = "\"'`()b[]r{}B<>atf"

    /// A surround replacement: one character, or a tag typed up to its ">"
    /// ("<em>", or after t: "em>").
    private func parseReplacement(_ keys: [VimKey], _ index: inout Int) -> ReplacementParse {
        guard index < keys.count else { return .incomplete }
        // f and ⌃F (evil-surround and embrace in Doom): a function name typed up to Return,
        // for "name(…)" and "(name …)".
        if keys[index] == .char("f") || keys[index] == .ctrl("f") {
            var name = String(keys[index] == .char("f") ? Self.functionCall : Self.prefixCall)
            index += 1
            while index < keys.count {
                let key = keys[index]
                index += 1
                switch key {
                case .char(let k): name.append(k)
                case .enter: return .done(name)
                case .backspace: if name.count > 1 { name.removeLast() }
                default: return .invalid
                }
            }
            return .incomplete
        }
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

    /// The characters a snipe searches for: `count` of them, or fewer ended by Return (none:
    /// repeat the last snipe). Backspace takes one back, and with none left, or Esc, gives up.
    private func readSnipe(_ keys: [VimKey], _ index: inout Int, count: Int, forward: Bool, inclusive: Bool, key: Character) -> MotionParse {
        var typed: [Character] = []
        while typed.count < count {
            guard index < keys.count else { return .incomplete }
            let next = keys[index]
            index += 1
            switch next {
            case .char(let c): typed.append(c)
            case .enter:
                if typed.isEmpty { return .done(.repeatFind(reverse: !forward)) }
                return .done(.snipe(typed, forward: forward, inclusive: inclusive, key: key))
            case .backspace:
                guard typed.count > 1 else { return .invalid }
                typed.removeLast()
            default:
                return .invalid
            }
        }
        return .done(.snipe(typed, forward: forward, inclusive: inclusive, key: key))
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
        case "'", "`":
            guard index < keys.count else { return .incomplete }
            guard case .char(let name) = keys[index], name.isASCII, name.isLetter else { return .invalid }
            index += 1
            return .done(.mark(name, exact: c == "`"))
        case "*": return .done(.searchWord(forward: true))
        case "#": return .done(.searchWord(forward: false))
        case "i" where textObjects, "a" where textObjects:
            guard index < keys.count else { return .incomplete }
            guard case .char(let kind) = keys[index], "wWpt\"'`()b[]{}B<>qgikjauxcf".contains(kind) else { return .invalid }
            index += 1
            return .done(.textObject(inner: c == "i", kind))
        case "f", "F", "t", "T":
            return readSnipe(keys, &index, count: 1, forward: c.isLowercase, inclusive: c == "f" || c == "F", key: Character(c.lowercased()))
        case "s" where !(textObjects && !inVisual), "S" where !textObjects:
            // s / S: Doom's evil-snipe, in place of vim's substitute (S stays surround in visual mode).
            return readSnipe(keys, &index, count: 2, forward: c == "s", inclusive: true, key: "s")
        case "z", "Z", "x", "X":
            // After an operator, evil-snipe's z / Z (inclusive) and x / X (exclusive).
            guard textObjects, !inVisual else {
                index -= 1
                return .invalid
            }
            return readSnipe(keys, &index, count: 2, forward: c.isLowercase, inclusive: c == "z" || c == "Z", key: Character(c.lowercased()))
        case "g":
            guard index < keys.count else { return .incomplete }
            // gn / gN after an operator or in visual mode: the next (last) search match as an object.
            if textObjects, case .char(let kind) = keys[index], kind == "n" || kind == "N" {
                index += 1
                return .done(.textObject(inner: true, kind))
            }
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
        let visualBefore = inVisual ? (mode, anchor, cursor) : nil
        let changesBefore = undoStack.count + undoTrimmed
        failed = false
        let effect = perform(command)
        // A macro or "." that stops says so for the key that played it, which fails too.
        if failed, message == nil { failureHint = failureHint(for: command) }
        // A change that couldn't run (ci" with no quotes, c; with no find): the typing meant
        // for insert mode is dropped until Esc instead of running as commands.
        if failed, playDepth == 0, !isRepeating, case .operate(.change, _) = command.action { ignoresTyping = true }
        // Remember a change for "." (a repeat records itself again, count and all, as in vim);
        // changes made in visual mode are not repeated, and "." after one does nothing rather
        // than repeat an older change.
        // A change that failed (ci" with no quotes) leaves the last one in place;
        // one that worked counts even when the text came out the same.
        if wasVisual, undoStack.count + undoTrimmed != changesBefore { lastChange = nil }
        // Leaving a visual selection keeps it for gv.
        if let visualBefore, !inVisual { lastVisual = (visualBefore.0, visualBefore.1, visualBefore.2) }
        if !wasVisual, Self.isChange(command), !failed {
            let change = (command.count, (command.register.map { [VimKey.char("\""), .char($0)] } ?? []) + command.keys)
            if mode == .insert { changeInProgress = change } else { lastChange = change }
        }
        return effect
    }

    /// "( )" for any of b ( ), "[ ]", "{ }" for B { }, "< >".
    private static func bracketPair(_ kind: Character) -> String {
        switch kind {
        case "[", "]": "[ ]"
        case "{", "}", "B": "{ }"
        case "<", ">": "< >"
        default: "( )"
        }
    }

    /// A few words on why `command` did nothing, after the keys typed.
    private func failureHint(for command: Command) -> String {
        let keys = Self.describe(typed)
        let motion: Motion? = switch command.action {
        case .motion(let motion): motion
        case .operate(_, let motion): motion
        default: nil
        }
        switch command.action {
        case .deleteSurround(let target), .changeSurround(let target, _):
            if target == "f" || target == "\u{6}" { return "\(keys): no function call around the cursor" }
        default: break
        }
        if case .simple(let name) = command.action, name == "moveDown" || name == "moveUp" {
            return "\(keys): no line \(name == "moveDown" ? "below" : "above")"
        }
        let reason: String = switch motion {
        // A count on j, k or $ only fails on the last (or first) line.
        case .down?, .lineEnd?: "no line below"
        case .up?: "no line above"
        case .wordBackward?: "at the start"
        case .snipe(let keys, _, _, _)?: "no “\(String(keys))” on the line"
        case .repeatFind?: "no more matches"
        case .textObject(_, let kind)? where "\"'`".contains(kind): "no \(kind)…\(kind) on this line"
        case .textObject(_, "B")?: "not inside a block"
        case .textObject(_, let kind)? where "([{<)]}>b".contains(kind): "not inside \(Self.bracketPair(kind))"
        case .textObject(_, "t")?: "not inside a tag"
        case .textObject(_, "q")?: "no quotes here"
        case .textObject(_, "a")?: "no argument here"
        case .textObject(_, "u")?: "no URL here"
        case .textObject(_, "x")?: "no attribute here"
        case .textObject(_, "c")?: "not in a comment"
        case .textObject(_, "f")?: "no function here"
        case .textObject(_, "n")?, .textObject(_, "N")?: "no match"
        default: "nothing to do"
        }
        return "\(keys): \(reason)"
    }

    /// Keys as typed, for the hint.
    private static func describe(_ keys: [VimKey]) -> String {
        keys.map { key in
            switch key {
            case .char(let c): String(c)
            case .ctrl(let c): "⌃\(c)"
            case .alt(let c): "⌥\(c.uppercased())"
            case .command(let c): "⌘⇧\(c)"
            case .escape: "Esc"
            case .enter: "↩"
            default: ""
            }
        }.joined()
    }

    private static func isChange(_ command: Command) -> Bool {
        switch command.action {
        case .motion: false
        case .deleteSurround, .changeSurround, .addSurround, .align: true
        case .operate(let op, _): op != .yank && op != .exchange
        case .simple(let name):
            ["x", "X", "D", "C", "J", "o", "O", "i", "I", "a", "A", "p", "P", "~", "increment", "decrement", "slurpForward", "slurpBackward", "barfForward", "barfBackward", "raise"].contains(name)
                || (name.hasPrefix("line") && name != "liney" && name != "lineX") || (name.hasPrefix("r") && name.count == 2)
        }
    }

    private mutating func perform(_ command: Command) -> VimEffect? {
        switch command.action {
        case .deleteSurround(let target):
            surround(target, count: command.count ?? 1, with: nil)
            return nil
        case .align(let right, let motion, let pattern, let firstOnly):
            if inVisual {
                let lines = (lineIndex(min(anchor, cursor)), lineIndex(max(anchor, cursor)))
                cursor = min(anchor, cursor)
                mode = .normal
                align(lines.0, lines.1, right: right, pattern: pattern, firstOnly: firstOnly)
            } else if let motion, let resolved = resolved(motion, count: command.count), let lines = lineRange(of: resolved, count: command.count ?? 1) {
                align(lines.0, lines.1, right: right, pattern: pattern, firstOnly: firstOnly)
            } else {
                failed = true
            }
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
                guard let motion = resolved(motion, count: command.count) else {
                    failed = true
                    return nil
                }
                operate(.surround, motion: motion, count: command.count ?? 1)
            } else {
                // yss: the line, without its indentation; a count takes more lines.
                let start = firstNonBlank(lineStart(cursor))
                let last = min(lineIndex(cursor) + (command.count ?? 1) - 1, lineStarts.count - 1)
                wrap(start..<lineEnd(lineStarts[last]), in: pair, trimming: true)
            }
            return nil
        case .motion(.textObject(let inner, "c")) where inVisual:
            // A comment over several lines selects a block, as evil-nerd-commenter's ic.
            guard let comment = commentObject() else {
                failed = true
                return nil
            }
            selectComment(comment, inner: inner)
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
        case .motion(.searchWord(let forward)) where inVisual && mode != .visualBlock:
            // evil-visualstar: search for the selected text from the cursor, the selection's
            // moving end, so viw# finds the word itself first, as in Doom.
            guard let range = selection, !range.isEmpty else { return nil }
            lastSearch = (String(text[range]), forward, false)
            mode = .normal
            _ = runMotion(.searchNext(reverse: false), count: command.count ?? 1)
            return nil
        case .motion(let motion):
            guard let motion = resolved(motion, count: command.count) else {
                failed = true
                return nil
            }
            if runMotion(motion, count: command.count ?? 1), let last = lastSnipe {
                switch motion {
                case .snipe, .repeatFind:
                    snipeRepeatKeys = (last.key, Character(last.key.uppercased()))
                default: break
                }
            }
            return nil
        case .operate(let op, let motion):
            if let motion {
                guard let motion = resolved(motion, count: command.count) else {
                    failed = true
                    return nil
                }
                // j and k under an operator aim for the remembered column; a failed
                // operator keeps it, as in vim.
                operate(op, motion: motion, count: command.count ?? 1)
                if !failed { wantedColumn = nil }
            } else if mode == .visualBlock {
                applyBlock(op)
                wantedColumn = nil
            } else if let range = selection {
                let linewise = mode == .visualLine
                let (first, last) = (lineIndex(min(anchor, cursor)), lineIndex(max(anchor, cursor)))
                mode = .normal
                if linewise { applyLines(op, first, last) } else { apply(op, to: range) }
                wantedColumn = nil
            }
            return nil
        case .simple(let name):
            // Escape, v and V keep the column j and k aim for (after $, the line's end), as in vim.
            // Block commands keep it too: after $, A appends at each line's end.
            if !["escape", "v", "V"].contains(name), !name.hasPrefix("block") { wantedColumn = nil }
            return runSimple(name, count: command.count)
        }
    }

    /// A count before G or gg names the line: G alone is the last line, gg the first.
    /// With a count, % goes to that percentage of the lines (50% is the middle), as in
    /// vim; past 100 it fails.
    private func resolved(_ motion: Motion, count: Int?) -> Motion? {
        if motion == .matchingBracket, let count {
            guard count <= 100 else { return nil }
            return .goToLine((count * lineStarts.count + 99) / 100)
        }
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
            case "v", "V", "block":
                let wanted: VimMode = name == "v" ? .visual : name == "V" ? .visualLine : .visualBlock
                mode = mode == wanted ? .normal : wanted
            case "blockO":
                // The other corner on the same line: the columns swap.
                let anchorColumn = anchor - lineStart(anchor), cursorColumn = cursor - lineStart(cursor)
                anchor = min(lineStart(anchor) + cursorColumn, lineEnd(anchor))
                cursor = min(lineStart(cursor) + anchorColumn, lineEnd(cursor))
            case "moveDown", "moveUp":
                moveLines(down: name == "moveDown", count: n)
                return nil
            case "slurpForward", "slurpBackward", "barfForward", "barfBackward", "raise":
                mode = .normal
                if name == "raise" { raise(count: n) } else { slurpOrBarf(name, count: n) }
                return nil
            case "visualIncrement", "visualDecrement", "visualIncrementEach", "visualDecrementEach":
                addToNumbersInSelection(name.contains("Increment") ? n : -n, eachMore: name.hasSuffix("Each"))
                return nil
            case "blockI", "blockA":
                startBlockInsert(append: name == "blockA")
                return nil
            case let name where name.hasPrefix("blockr"):
                guard let replacement = name.dropFirst(6).first else { break }
                let ranges = blockSelection ?? []
                let corner = blockCorner()
                checkpoint()
                for range in ranges { for index in range { text[index] = replacement } }
                mode = .normal
                cursor = corner
            case "p", "P":
                replaceSelection()
            case ":":
                // As vim: the command line starts with the selection's lines.
                mode = .commandLine
                commandLine = ":'<,'>"
                return nil
            default: break
            }
            clampCursor()
            return nil
        }
        switch name {
        case "escape": break
        case "x": operate(.delete, motion: .right, count: n)
        case "X": operate(.delete, motion: .left, count: n)
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
        case "increment", "decrement": addToNumber(name == "increment" ? n : -n)
        case "slurpForward", "slurpBackward", "barfForward", "barfBackward": slurpOrBarf(name, count: n)
        case "raise": raise(count: n)
        case "moveDown", "moveUp": moveLines(down: name == "moveDown", count: n)
        case "block":
            anchor = cursor
            mode = .visualBlock
        case "R":
            checkpoint()
            mode = .replace
            replaced = []
            replaceKeys = []
            replaceCount = min(n, 10_000)
        case "gn", "gN":
            guard let match = searchMatch(forward: name == "gn") else {
                failed = true
                return nil
            }
            mode = .visual
            anchor = match.lowerBound
            cursor = match.upperBound - 1
        case "gv":
            guard let last = lastVisual else {
                failed = true
                return nil
            }
            mode = last.mode
            anchor = min(last.anchor, text.count)
            cursor = min(last.cursor, text.count)
        case "&":
            // & repeats the last :s on this line, without its flags, as vim does.
            guard var last = lastSubstitute else {
                message = "E35: No previous regular expression"
                failed = true
                return nil
            }
            last.range = .current
            last.global = false
            last.ignoreCase = nil
            substitute(last)
        case "q":
            // vim: "The 'q' command is disabled while executing a register".
            if playDepth == 0 { stopRecording() }
        case "exchangeCancel": exchangeMark = nil
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
            } else if name.hasPrefix("mark"), name.count == 5, let mark = name.last {
                marks[mark] = cursor
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
            // In visual mode the cursor may stop on the line's end, as in vim, so a
            // column past it takes the line break.
            let last = inVisual ? lineEnd(start) : max(lineEnd(start) - 1, start)
            return Target(position: column == .max ? last : min(start + column, last), kind: .linewise)
        case .wordForward(let big):
            var position = cursor
            for _ in 0..<count { position = wordForward(from: position, big: big) }
            return Target(position: position, kind: .exclusive)
        case .wordBackward(let big):
            var position = cursor
            for _ in 0..<count {
                if position == 0 {
                    // As vim's bck_word: a word that reaches the text's start ends the count
                    // there. Only a step that has to start from an empty first line fails,
                    // operator and all, and the cursor stays at the start.
                    if position != cursor, text.first != "\n" { break }
                    cursor = 0
                    return nil
                }
                position = wordBackward(from: position, big: big)
            }
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
                if forOperator { return Target(position: n, kind: .inclusive) }
                if text.last == "\n", cursor < n { return Target(position: n, kind: .exclusive) }
                if position == cursor { return nil }
            }
            return Target(position: position, kind: .inclusive)
        case .lineStart:
            return Target(position: lineStart(cursor), kind: .exclusive)
        case .firstNonBlank:
            return Target(position: firstNonBlank(lineStart(cursor)), kind: .exclusive)
        case .lineEnd:
            // As for j: a count on the last line fails; elsewhere it stops at the last line.
            // Failing still makes j and k aim for the line's end, as in vim.
            guard count == 1 || lineIndex(cursor) + 1 < lineStarts.count else {
                wantedColumn = .max
                return nil
            }
            let line = min(lineIndex(cursor) + count - 1, lineStarts.count - 1)
            let end = lineEnd(lineStarts[line])
            // d$ on an empty line has nothing to take; v$ takes the line break.
            if end == lineStarts[line] || inVisual { return Target(position: end, kind: .inclusive) }
            return Target(position: end - 1, kind: .inclusive)
        case .goToLine(let number):
            let line = min(max(number ?? lineStarts.count, 1), lineStarts.count) - 1
            return Target(position: firstNonBlank(lineStarts[line]), kind: .linewise)
        case .snipe(let keys, let forward, let inclusive, let key):
            lastSnipe = (keys, forward, inclusive, count, key)
            return snipe(keys, forward: forward, inclusive: inclusive, count: count, wholeText: false, forOperator: forOperator)
        case .repeatFind(let reverse):
            guard let last = lastSnipe else { return nil }
            // A repeat searches the whole text (Doom's evil-snipe-repeat-scope is 'visible).
            return snipe(last.keys, forward: last.forward != reverse, inclusive: last.inclusive, count: count * last.count, wholeText: true, forOperator: forOperator)
        case .matchingBracket:
            return matchingBracket().map { Target(position: $0, kind: .inclusive) }
        case .paragraphForward, .paragraphBackward:
            let starts = lineStarts
            // } and { stop at empty lines only; a line of blanks is part of a paragraph, as in vim
            // (unlike ip and ap).
            func blank(_ line: Int) -> Bool {
                starts[line] == (line + 1 < starts.count ? starts[line + 1] - 1 : n)
            }
            var line = lineIndex(cursor)
            let forward = motion == .paragraphForward
            let step = forward ? 1 : -1
            for index in 0..<count {
                while line + step >= 0, line + step < starts.count, blank(line) { line += step }
                while line + step >= 0, line + step < starts.count, !blank(line + step) { line += step }
                if line + step >= 0, line + step < starts.count { line += step } else {
                    // The text's end counts as one more paragraph boundary; a count past it fails, as in vim.
                    guard index == count - 1 else { return nil }
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
        case .mark(let name, let exact):
            guard let position = marks[name] else {
                message = "E20: Mark not set"
                return nil
            }
            let at = min(position, text.count)
            return exact ? Target(position: at, kind: .exclusive) : Target(position: firstNonBlank(lineStart(at)), kind: .linewise)
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

    /// evil-snipe's seek with Doom's settings: matches on the line (the whole text for a
    /// repeat), lowercase keys matching either case (smart case) and accents folded
    /// (char-fold), the count-th match, never one at the cursor; t and x search from one
    /// further on. Where the cursor lands follows evil-snipe: on the match (f, s), before it
    /// (t), past it for an operator, on its last character in visual mode. The motion is
    /// exclusive, as evil-snipe's motions are.
    private func snipe(_ keys: [Character], forward: Bool, inclusive: Bool, count: Int, wholeText: Bool, forOperator: Bool) -> Target? {
        let length = keys.count
        let ignoreCase = !keys.contains(where: \.isUppercase)
        func fold(_ c: Character) -> String {
            String(c).folding(options: ignoreCase ? [.diacriticInsensitive, .caseInsensitive] : [.diacriticInsensitive], locale: nil)
        }
        let wanted = keys.map(fold)
        func matches(_ at: Int) -> Bool {
            guard at >= 0, at + length <= text.count else { return false }
            return (0..<length).allSatisfy { fold(text[at + $0]) == wanted[$0] }
        }
        var found: Int?
        var remaining = max(count, 1)
        if forward {
            let limit = wholeText ? text.count : lineEnd(cursor)
            var at = cursor + 1 + (inclusive ? 0 : 1)
            while at + length <= limit {
                if matches(at) {
                    remaining -= 1
                    if remaining == 0 { found = at; break }
                    // The next of a count starts after this match, as re-search-forward's count does.
                    at += length
                    continue
                }
                at += 1
            }
        } else {
            let end = inclusive ? cursor : cursor - 1
            let low = wholeText ? 0 : lineStart(cursor)
            var at = end - length
            while at >= low {
                if matches(at) {
                    remaining -= 1
                    if remaining == 0 { found = at; break }
                    at -= length
                    continue
                }
                at -= 1
            }
        }
        guard let match = found else { return nil }
        let position: Int
        if !forward {
            position = inclusive ? match : match + length
        } else if forOperator {
            position = inclusive ? match + length : match
        } else if inVisual {
            position = inclusive ? match + length - 1 : match - length + (length > 1 ? 1 : 0)
        } else {
            position = inclusive ? match : match - length + (length > 1 ? 1 : 0)
        }
        return Target(position: position, kind: .exclusive)
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
        // A word object ends like a motion: it can be exclusive, and the operator adjusts it as vim does.
        if case .textObject(let inner, let kind) = motion, kind == "w" || kind == "W" {
            let word = wordObject(inner: inner, big: kind == "W", count: count)
            guard word.found else {
                cursor = word.end
                clampCursor()
                failed = true
                return
            }
            // The empty end line's word is the line break before it, taken as is.
            if cursor == text.count {
                apply(op, to: word.start..<text.count)
                return
            }
            apply(op, from: word.start, to: Target(position: word.end, kind: word.inclusive ? .inclusive : .exclusive))
            return
        }
        if case .textObject(let inner, "c") = motion {
            guard let comment = commentObject() else {
                failed = true
                return
            }
            if !inner, comment.lines.count > 1, op == .delete {
                // Doom's dac on comment lines takes the lines, keeping the cursor's column.
                let column = cursor - lineStart(cursor)
                applyLines(.delete, comment.lines.lowerBound, comment.lines.upperBound - 1)
                let start = lineStart(cursor)
                cursor = start + min(column, max(lineEnd(start) - start - 1, 0))
                return
            }
            if inner, comment.lines.count > 1 {
                selectComment(comment, inner: true)
                applyBlock(op)
                clampCursor()
                return
            }
            apply(op, to: inner ? comment.inner : comment.outer)
            return
        }
        if case .textObject(let inner, let kind) = motion, "ikj".contains(kind) {
            guard let (lines, _) = textObject(inner: inner, kind, count: count) else {
                failed = true
                return
            }
            operateOnIndent(op, lines: lines)
            return
        }
        if case .textObject(let inner, let kind) = motion {
            guard let (range, linewise) = textObject(inner: inner, kind, count: count) else {
                failed = true
                return
            }
            if linewise {
                guard !range.isEmpty else { return }
                let column = lineIndex(cursor) == range.lowerBound ? 0 : cursor - lineStart(cursor)
                applyLines(op, range.lowerBound, range.upperBound - 1)
                // yap and yip go to the block's first line, at its start.
                if op == .yank { cursor = lineStarts[range.lowerBound] }
                // Doom's dif keeps the cursor's column (evil-start-of-line is off), but from the
                // function's first line it goes to the line's start.
                if op == .delete, kind == "f", mode == .normal {
                    let start = lineStart(cursor)
                    cursor = start + min(column, max(lineEnd(start) - start - 1, 0))
                }
            } else if op == .indent || op == .outdent {
                applyLines(op, lineIndex(range.lowerBound), lineIndex(max(range.upperBound - 1, range.lowerBound)))
            } else if !range.isEmpty || op == .change || op == .yank {
                apply(op, to: range)
            } else {
                // Nothing between (di( on "()"): no change, but the cursor goes there, as in vim.
                cursor = range.lowerBound
                clampCursor()
            }
            return
        }
        let start = cursor
        if case .wordForward(let big) = motion {
            // cw on a word changes to its end, not up to the next word.
            if op == .change, start < text.count, characterClass(start, big: big) != 0 {
                var end = start - 1
                for _ in 0..<count { end = wordEnd(from: end, big: big) }
                apply(op, from: start, to: Target(position: min(end, text.count), kind: .inclusive))
                return
            }
            // As vim's fwd_word for an operator: the last word stops at its line's end rather
            // than take the line break; a failure at the text's end still takes what it moved over.
            var position = start
            _ = vimForwardWord(&position, count: count, big: big, stopAtLineEnd: true)
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
            // A case change leaves the cursor where the motion began or ended, whichever is first.
            if [.upper, .lower, .toggleCase].contains(op) { cursor = min(start, target.position) }
        case .inclusive, .exclusive:
            let low = min(start, target.position)
            var high = max(start, target.position)
            // An inclusive end on a line's end takes the line, not its line break, as in vim.
            if target.kind == .inclusive, high < text.count, text[high] != "\n" { high += 1 }
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
            // An empty yank still yanks (nothing), as vim's does.
            guard high > low || op == .change || op == .yank else { return }
            // c$ (C) or ce on an empty line takes the empty text, so the register is emptied, as in
            // vim; with no lines there is nothing to take, and the register stays.
            if op == .change, high == low, target.kind == .inclusive, !(noLines && text.isEmpty) { store(VimRegister(text: "", linewise: false), yank: false) }
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
        // gcc with a count past the last line still comments it, as evil-nerd-commenter does.
        guard count == 1 || line + 1 < lineStarts.count || op == .comment else {
            failed = true
            return
        }
        let last = min(line + count - 1, lineStarts.count - 1)
        let start = cursor
        applyLines(op, line, last)
        // As for gUj: 2gUU keeps the column, gUU goes no further right than the first non-blank.
        if [.upper, .lower, .toggleCase].contains(op) { cursor = min(start, firstNonBlank(lineStarts[last])) }
    }

    /// An operator on whole lines, `first` through `last`.
    private mutating func applyLines(_ op: Operator, _ first: Int, _ last: Int) {
        if op == .surround { return wrapLines(first, last, in: surroundPair, indenting: false) }
        if op == .format { return format(first, last) }
        if op == .comment { return toggleComment(first, last) }
        if op == .reindent {
            reindentRequest = first...last
            return
        }
        if op == .exchange {
            let starts = lineStarts
            // The lines' text without the last line break, so the last line swaps cleanly.
            return exchange(starts[first]..<lineEnd(starts[last]), linewise: true)
        }
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
            // With no lines there is nothing to delete, and the register stays, as in vim.
            guard !(noLines && text.isEmpty) else { return }
            store(VimRegister(text: taken, linewise: true), yank: op == .yank)
            checkpoint(at: start)
            if last + 1 < starts.count {
                text.removeSubrange(start..<starts[last + 1])
            } else {
                // The last line takes the line break before it.
                noLines = first == 0
                text.removeSubrange(max(start - 1, 0)..<text.count)
            }
            cursor = firstNonBlank(lineStarts[min(first, lineStarts.count - 1)])
        case .change:
            if !(noLines && text.isEmpty) { store(VimRegister(text: taken, linewise: true), yank: op == .yank) }
            checkpoint(at: start)
            // cc keeps one line, emptied but for its indentation.
            let indent = Array(text[start..<firstNonBlank(start)])
            text.replaceSubrange(start..<bodyEnd, with: indent)
            cursor = start + indent.count
            beginInsert()
            return
        case .surround, .format, .comment, .exchange, .reindent:
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
        if op == .exchange { return exchange(range, linewise: false) }
        if op == .reindent {
            reindentRequest = lineIndex(range.lowerBound)...lineIndex(max(range.upperBound - 1, range.lowerBound))
            return
        }
        if op == .format || op == .comment {
            let first = lineIndex(range.lowerBound), last = lineIndex(max(range.upperBound - 1, range.lowerBound))
            return op == .format ? format(first, last) : toggleComment(first, last)
        }
        let taken = String(text[range])
        switch op {
        case .yank:
            store(VimRegister(text: taken, linewise: false), yank: true)
            cursor = range.lowerBound
        case .delete, .change:
            // An empty range (cl on an empty line) keeps what was taken before.
            if !range.isEmpty { store(VimRegister(text: taken, linewise: false), yank: false) }
            checkpoint(at: range.lowerBound)
            text.removeSubrange(range)
            cursor = range.lowerBound
            if op == .change {
                beginInsert()
                return
            }
        case .surround, .format, .comment, .exchange, .reindent:
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
        // > skips only empty lines; a line of blanks is indented too, as in vim.
        case .indent: block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : String(repeating: " ", count: TextTransforms.indentWidth) + $0 }.joined(separator: "\n")
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
            // On the last line 2J fails; a larger count joins nothing and goes to the line's start, as in vim.
            if count > 2 { cursor = lineStart(cursor) } else { failed = true }
            return
        }
        checkpoint()
        // As vim's do_join: whether a space goes in depends on the line joined just before
        // (its last character), not on the text joined so far, so an empty line between
        // starts afresh. Nothing is trimmed but the next line's indentation.
        let first = lineStart(cursor)
        var joined = lineEnd(cursor) - first
        var lastCharacter: Character? = joined > 0 ? text[lineEnd(cursor) - 1] : nil
        for _ in 0..<(count - 1) {
            let end = lineEnd(cursor)
            guard end < text.count else { break }
            var next = end + 1
            while next < text.count, text[next] == " " || text[next] == "\t" { next += 1 }
            let pieceEnd = lineEnd(next)
            let piece = pieceEnd - next
            // One space, unless the line is empty, starts with ")", nothing came before,
            // or what came before ends in a blank.
            let space = piece > 0 && text[next] != ")" && joined > 0 && lastCharacter != " " && lastCharacter != "\t"
            let nextLast: Character? = piece > 0 ? text[pieceEnd - 1] : nil
            text.replaceSubrange(end..<next, with: space ? [" "] : [])
            joined += piece + (space ? 1 : 0)
            lastCharacter = nextLast
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
        if register.blockwise {
            putBlock(register.text, after: after, count: count)
            return
        }
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

    /// A yanked block pasted as a block: each row into the next line at the cursor's column
    /// (after it for p), short lines padded with spaces, lines added at the end if needed.
    private mutating func putBlock(_ block: String, after: Bool, count: Int) {
        let rows = block.components(separatedBy: "\n").map { String(repeating: $0, count: count) }
        let line = lineIndex(cursor)
        let column = cursor - lineStart(cursor) + (after && !lineIsEmpty(cursor) ? 1 : 0)
        for (offset, row) in rows.enumerated() {
            if line + offset >= lineStarts.count { text.append("\n") }
            let start = lineStarts[line + offset], length = lineEnd(start) - start
            let padding = Array(repeating: Character(" "), count: max(column - length, 0))
            text.insert(contentsOf: padding + Array(row), at: start + min(column, length))
        }
        cursor = lineStarts[line] + column
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
        case "w", "W":
            // As visual mode selects it: the end is included.
            let word = wordObject(inner: inner, big: kind == "W", count: count)
            return word.found ? (word.start..<max(word.start, min(word.end + 1, text.count)), false) : nil
        case "\"", "'", "`": return quoteObject(inner: inner, quote: kind).map { ($0, false) }
        case "(", ")", "b": return bracketObject(inner: inner, open: "(", close: ")", count: count)
        case "[", "]": return bracketObject(inner: inner, open: "[", close: "]", count: count)
        case "{", "}": return bracketObject(inner: inner, open: "{", close: "}", count: count)
        case "B": return anyBlockObject(inner: inner, count: count)
        case "<", ">": return bracketObject(inner: inner, open: "<", close: ">", count: count)
        case "p": return paragraphObject(inner: inner, count: count).map { ($0, true) }
        case "t": return tagObject(inner: inner, count: count).map { ($0, false) }
        case "q": return anyQuoteObject(inner: inner, count: count).map { ($0, false) }
        // Doom's ig / ag (+evil:whole-buffer-txtobj): all the text, as characters.
        case "g": return (0..<text.count, false)
        case "a": return argumentObject(inner: inner, count: count).map { ($0, false) }
        case "u": return urlObject(inner: inner).map { ($0, false) }
        case "c": return commentObject().map { (inner ? $0.inner : $0.outer, false) }
        case "n", "N": return searchMatch(forward: kind == "n").map { ($0, false) }
        case "f": return defunObject().map { ($0, true) }
        case "x": return xmlAttributeObject(inner: inner).map { ($0, false) }
        case "i", "k", "j": return indentObject(inner: inner, kind).map { ($0, true) }
        default: return nil
        }
    }

    // MARK: - Marks

    /// Moves the marks with what changed since they were last checked: a mark after the
    /// change shifts by its length, one inside it goes to its start.
    private mutating func moveMarks() {
        defer { marksText = text }
        guard !marks.isEmpty, marksText != text else { return }
        let prefix = zip(marksText, text).prefix { $0 == $1 }.count
        let room = min(marksText.count, text.count) - prefix
        let suffix = min(zip(marksText.reversed(), text.reversed()).prefix { $0 == $1 }.count, room)
        let oldEnd = marksText.count - suffix, delta = text.count - marksText.count
        for (name, at) in marks {
            if at >= oldEnd { marks[name] = at + delta } else if at > prefix { marks[name] = prefix }
        }
    }

    // MARK: - gn

    /// gn's match (ROADMAP C36): the last search's match the cursor is on, else the next one
    /// after the cursor (gN: the one before), wrapping as / does. Nil with no search or no
    /// match. (evil after a jump such as gg skips one match more; that isn't copied.)
    private func searchMatch(forward: Bool) -> Range<Int>? {
        guard let last = lastSearch, !last.pattern.isEmpty else { return nil }
        let length = last.pattern.count
        // A match the cursor is on: the last one starting at or before it.
        if let before = search(last.pattern, from: min(cursor + 1, text.count), forward: false, wholeWord: last.wholeWord),
           before <= cursor, cursor < before + length {
            return before..<(before + length)
        }
        guard let at = search(last.pattern, from: cursor, forward: forward, wholeWord: last.wholeWord) else { return nil }
        return at..<(at + length)
    }

    // MARK: - Doom's text objects

    /// Doom's if / af (+evil:defun-txtobj, Emacs's defun thing), as whole lines: the
    /// function around the cursor and one blank line after it. Doom asks the major mode; the
    /// window has none, so for Lisp text (as gc guesses it) a function is a top-level form, a
    /// bracket at a line's start, from the nearest one at or above the cursor's line to its
    /// closing bracket. Other text: the nearest line above the cursor, less indented, that
    /// ends in ":" or "{", through the more indented lines after it and a closing bracket at
    /// its own indentation.
    private func defunObject() -> Range<Int>? {
        let lines = string.components(separatedBy: "\n")
        let starts = lineStarts
        let here = lineIndex(cursor)
        func blank(_ i: Int) -> Bool { lines[i].allSatisfy { $0 == " " || $0 == "\t" } }
        func indent(_ i: Int) -> Int { lines[i].prefix { $0 == " " || $0 == "\t" }.count }
        var first: Int, last: Int
        if Self.commentString(for: string) == ";;" || lines.contains(where: { $0.hasPrefix("(") }) {
            guard let top = (0...here).last(where: { lines[$0].first.map { "([{".contains($0) } ?? false }) else { return nil }
            let open = text[starts[top]]
            let close: Character = open == "(" ? ")" : open == "[" ? "]" : "}"
            guard let end = matchingClose(open, close, from: starts[top]) else { return nil }
            (first, last) = (top, lineIndex(end))
        } else {
            let base = blank(here) ? Int.max : indent(here)
            guard let top = (0...here).last(where: { i in
                !blank(i) && (i == here ? true : indent(i) < base) && ["{", ":"].contains(lines[i].trimmingCharacters(in: .whitespaces).last ?? " ")
            }) else { return nil }
            first = top
            last = top
            while last + 1 < lines.count, blank(last + 1) || indent(last + 1) > indent(top) || (indent(last + 1) == indent(top) && lines[last + 1].trimmingCharacters(in: .whitespaces).first.map { ")]}".contains($0) } == true) {
                last += 1
                if indent(last) == indent(top), !blank(last) { break }
            }
            // Blank lines at the end are not the function's; one is added below.
            while last > first, blank(last) { last -= 1 }
        }
        guard here <= last + 1 else { return nil }
        // One blank line after, but not the empty end after a final line break (no line to Emacs).
        let realLines = text.last == "\n" ? lines.count - 1 : lines.count
        if last + 1 < realLines, blank(last + 1) { last += 1 }
        return first..<(last + 1)
    }

    /// A comment for Doom's ic / ac (evil-nerd-commenter): its lines; the inner text of a
    /// one-line comment (from its first word to the line's end); the columns of the block a
    /// comment over several lines makes; and the outer range, comment characters included.
    private struct Comment {
        var lines: Range<Int>
        var inner: Range<Int>
        var columns: Range<Int>
        var outer: Range<Int>
    }

    /// A port of evilnc-get-comment-bounds, with Emacs's comment face read as: from the comment
    /// characters (the guessed comment string's) to the line's end, its line break included.
    /// Blanks outside a comment count as comment, as evil-nerd-commenter treats them.
    private func commentObject() -> Comment? {
        let marker = Self.commentString(for: string)
        let start = marker == ";;" ? ";" : marker
        let starts = lineStarts, n = text.count
        // Where each line's comment begins, if it has one (outside a "…" string).
        let commentStarts: [Int?] = starts.map { lineStartIndex in
            var inString = false, i = lineStartIndex
            let end = lineEnd(lineStartIndex)
            while i < end {
                if text[i] == "\\" { i += 2; continue }
                if text[i] == "\"" { inString.toggle() }
                if !inString, String(text[i..<min(i + start.count, end)]) == start { return i }
                i += 1
            }
            return nil
        }
        func inComment(_ i: Int) -> Bool {
            guard i >= 0, i < n, let from = commentStarts[lineIndex(i)] else { return false }
            return i >= from
        }
        func counts(_ i: Int) -> Bool { i >= 0 && i < n && (inComment(i) || text[i] == " " || text[i] == "\t") }
        var b = cursor, e = cursor
        while counts(b - 1) { b -= 1 }
        while counts(e + 1) { e += 1 }
        // Blanks after the last comment (the next line's indentation) are not part of it.
        if let last = (lineIndex(b)...lineIndex(e)).last(where: { commentStarts[$0].map { $0 <= e } ?? false }), lineIndex(e) > last {
            e = lineEnd(starts[last])
        }
        // A blank last line is left out.
        let lastStart = lineStart(e)
        if text[lastStart..<lineEnd(e)].allSatisfy({ $0 == " " || $0 == "\t" }) { e = lastStart - 1 }
        guard b < e else { return nil }
        let firstLine = lineIndex(b), lastLine = lineIndex(e)
        let oneLine = e <= lineEnd(b)
        if oneLine {
            while b < e, !inComment(b) { b += 1 }
            while e > b, !inComment(e) { e -= 1 }
            guard b < e else { return nil }
        }
        guard inComment(b) || !oneLine else { return nil }
        // The first word after the comment characters, as forward-word then backward-word.
        var word = b
        while word < n, !(text[word].isLetter || text[word].isNumber) { word += 1 }
        let innerEnd = lineEnd(lastLine < starts.count ? starts[lastLine] : b)
        let inner = min(word, innerEnd)..<innerEnd
        // The block: from the leftmost first comment letter to the last line's end.
        let bodyColumns = (firstLine...lastLine).compactMap { line -> Int? in
            guard let from = commentStarts[line] else { return nil }
            var i = from
            while i < lineEnd(starts[line]), text[i] == start.first! || text[i] == " " || text[i] == "\t" { i += 1 }
            return i < lineEnd(starts[line]) ? i - starts[line] : nil
        }
        let left = bodyColumns.min() ?? 0
        let right = lineEnd(starts[lastLine]) - starts[lastLine]
        return Comment(lines: firstLine..<(lastLine + 1), inner: inner, columns: left..<max(left, right), outer: b..<e)
    }

    /// Selects a comment in visual mode: characters for one line, a block for several.
    private mutating func selectComment(_ comment: Comment, inner: Bool) {
        if inner, comment.lines.count > 1 {
            let starts = lineStarts
            mode = .visualBlock
            wantedColumn = nil
            anchor = starts[comment.lines.lowerBound] + comment.columns.lowerBound
            cursor = starts[comment.lines.upperBound - 1] + max(comment.columns.upperBound - 1, comment.columns.lowerBound)
            return
        }
        let range = inner ? comment.inner : comment.outer
        guard !range.isEmpty else { return }
        if mode != .visual { mode = .visual }
        anchor = range.lowerBound
        cursor = range.upperBound - 1
    }

    /// Doom's iB / aB (evil-textobj-anyblock, set to ( { [ < in Doom's evil module): of the
    /// bracket pairs around the cursor, the smallest; around none, the next pair after it.
    private func anyBlockObject(inner: Bool, count: Int) -> (Range<Int>, Bool)? {
        let pairs: [(Character, Character)] = [("(", ")"), ("{", "}"), ("[", "]"), ("<", ">")]
        let around = pairs.filter { open, close in
            (cursor < text.count && text[cursor] == open) || enclosingOpen(open, close, before: cursor) != nil
        }
        // A count past a kind's depth takes its outermost pair, as evil does.
        let sized = around.compactMap { pair -> (pair: (Character, Character), count: Int, size: Int)? in
            var depth = 1, position = cursor
            while let open = enclosingOpen(pair.0, pair.1, before: position) {
                depth += 1
                position = open
            }
            for level in stride(from: min(max(count, 1), depth), through: 1, by: -1) {
                if let (outer, _) = bracketObject(inner: false, open: pair.0, close: pair.1, count: level) { return (pair, level, outer.count) }
            }
            return nil
        }
        if let best = sized.min(by: { $0.size < $1.size }) {
            return bracketObject(inner: inner, open: best.pair.0, close: best.pair.1, count: best.count)
        }
        guard let next = (cursor..<text.count).first(where: { i in pairs.contains { $0.0 == text[i] } }),
              let pair = pairs.first(where: { $0.0 == text[next] }) else { return nil }
        return bracketObject(inner: inner, open: pair.0, close: pair.1, count: count)
    }

    /// Doom's iu / au (+evil:inner-url-txtobj, Emacs's url thing): au is the URL under the
    /// cursor; iu leaves out its scheme and "://" and anything from its last ? or #. A URL
    /// needs a scheme ("www.example.com" alone is not one), stops at blanks and
    /// "'<>[]^`{}, and drops a last . , ; (unless the cursor is just after them) and an
    /// unmatched ) as Emacs does.
    private func urlObject(inner: Bool) -> Range<Int>? {
        let stops: Set<Character> = ["\"", "'", "<", ">", "[", "]", "^", "`", "{", "}"]
        func isURLCharacter(_ i: Int) -> Bool { i >= 0 && i < text.count && !text[i].isWhitespace && !stops.contains(text[i]) }
        // As Emacs's things, the cursor may also sit just after the URL.
        let at = isURLCharacter(cursor) ? cursor : cursor - 1
        guard isURLCharacter(at) else { return nil }
        var low = at, high = at + 1
        while isURLCharacter(low - 1) { low -= 1 }
        while isURLCharacter(high) { high += 1 }
        let token = Array(text[low..<high])
        // The scheme: letters (then letters, digits, + . -) and ":", before "//" or a known "mailto:"-style name.
        let bare: Set<String> = ["mailto", "tel", "sms", "news", "urn", "data", "about", "magnet", "geo"]
        var start: Int?
        for i in token.indices where token[i].isASCII && token[i].isLetter && (i == 0 || !(token[i - 1].isLetter || token[i - 1].isNumber || "+.-".contains(token[i - 1]))) {
            var j = i
            while j < token.count, token[j].isASCII, token[j].isLetter || token[j].isNumber || "+.-".contains(token[j]) { j += 1 }
            guard j < token.count, token[j] == ":" else { continue }
            let slashes = j + 2 < token.count && token[j + 1] == "/" && token[j + 2] == "/"
            if slashes || bare.contains(String(token[i..<j]).lowercased()) {
                start = low + i
                break
            }
        }
        guard let start, start <= at else { return nil }
        var end = high
        while end > start {
            let last = text[end - 1]
            // Just after the URL, Emacs keeps its last . , or ;.
            if ".,;".contains(last), at == cursor {
                end -= 1
            } else if last == ")", !text[start..<end].contains("(") {
                end -= 1
            } else {
                break
            }
        }
        // On the character just after the URL counts; past a dropped ")" does not.
        guard at < end || (at == end && at == cursor) else { return nil }
        if !inner { return start..<end }
        guard let scheme = (start..<max(start, end - 2)).first(where: { text[$0] == ":" && text[$0 + 1] == "/" && text[$0 + 2] == "/" }) else { return nil }
        let innerEnd = (scheme + 3..<end).last(where: { text[$0] == "?" || text[$0] == "#" }) ?? end
        return (scheme + 3)..<max(scheme + 3, innerEnd)
    }

    /// Doom's ix / ax (exato): an XML attribute, `name="value"` or `name=value`; ax adds the
    /// space before it. A port of exato.el: the "=" is found from the value's string or the
    /// word under the cursor, else the next "=" before the tag's ">"; strings are "…" only.
    private func xmlAttributeObject(inner: Bool) -> Range<Int>? {
        let n = text.count
        // The "…" strings, read from the top with backslash escapes.
        var strings: [(Int, Int)] = []
        var open: Int?
        var i = 0
        while i < n {
            if text[i] == "\\" { i += 2; continue }
            if text[i] == "\"" {
                if let start = open { strings.append((start, i)); open = nil } else { open = i }
            }
            i += 1
        }
        /// bounds-of-evil-string-at-point here or one on: the string's quotes.
        func string(at p: Int) -> (Int, Int)? {
            strings.first { $0.0 < p && p <= $0.1 } ?? strings.first { $0.0 < p + 1 && p + 1 <= $0.1 }
        }
        func alpha(_ p: Int) -> Bool { p >= 0 && p < n && text[p].isLetter }
        var delimiter: Int?
        if let (start, _) = string(at: cursor) {
            if start > 0, text[start - 1] == "=" { delimiter = start - 1 }
        } else if alpha(cursor) {
            var p = cursor
            while alpha(p - 1) { p -= 1 }
            if p > 0, text[p - 1] == "=" { delimiter = p - 1 }
        }
        if delimiter == nil {
            var p = cursor
            if p < n, text[p] == " " { while p < n, " \n\t".contains(text[p]) { p += 1 } }
            let close = (p..<n).first { text[$0] == ">" } ?? n
            let quoted = (p..<max(p, close - 1)).first { text[$0] == "=" && text[$0 + 1] == "\"" }
            delimiter = quoted ?? (p..<close).first { text[$0] == "=" }
        }
        guard let delimiter else { return nil }
        var start = delimiter
        while start > 0, text[start - 1] != " " { start -= 1 }
        let finish: Int
        if delimiter + 1 < n, text[delimiter + 1] == "\"" {
            guard let (_, close) = string(at: delimiter + 1) else { return nil }
            finish = close
        } else if alpha(delimiter + 1) {
            var p = delimiter + 1
            while alpha(p + 1) { p += 1 }
            finish = p
        } else {
            return nil
        }
        return (inner ? start : max(start - 1, 0))..<(finish + 1)
    }

    /// Doom's ia / aa (evil-args): one argument between ( [ { and , or ; and the closer.
    /// ia is the argument; aa adds the delimiter and one space after it, or for the last
    /// argument the delimiter before it. Only , and ; split arguments, as in evil-args, so a
    /// Clojure form is one argument. A port of evil-args.el, edges included.
    private func argumentObject(inner: Bool, count: Int) -> Range<Int>? {
        let openers: Set<Character> = ["(", "{", "["], closers: Set<Character> = [")", "}", "]"], delimiters: Set<Character> = [",", ";"]
        let all = openers.union(closers).union(delimiters)
        let n = text.count
        func at(_ i: Int, _ set: Set<Character>) -> Bool { i >= 0 && i < n && set.contains(text[i]) }
        /// evil-jump-item on a bracket: the matching one, any kind counting.
        func jump(_ i: Int) -> Int? {
            let step = at(i, openers) ? 1 : -1
            var depth = 0, j = i
            while j >= 0, j < n {
                if at(j, openers) { depth += step } else if at(j, closers) { depth -= step }
                if depth == 0 { return j }
                j += step
            }
            return nil
        }
        func backwardDelimiter(_ from: Int, count: Int) -> Int? {
            var point = from, count = count
            while count > 0 {
                guard let found = (0..<max(point, 0)).last(where: { at($0, all) }) else {
                    return max(lineStart(point) - 1, 0)
                }
                point = found
                while at(point, closers) {
                    guard let open = jump(point) else { return nil }
                    point = open - 1
                }
                if at(point, openers) { return point }
                if at(point, delimiters) {
                    count -= 1
                    if count <= 0 { return point }
                }
            }
            return point
        }
        func forwardDelimiter(_ from: Int, count: Int) -> Int? {
            var point = from, count = count
            while count > 0 {
                guard let found = (min(point, n)..<n).first(where: { at($0, all) }) else { return lineEnd(point) }
                point = found
                while at(point, openers) {
                    guard let close = jump(point) else { return nil }
                    point = close + 1
                }
                if at(point, closers) { return point }
                if at(point, delimiters) {
                    count -= 1
                    if count <= 0 { return point }
                    point += 1
                }
            }
            return point
        }
        /// evil-args--backward-arg-no-skip: after the delimiter before, one space and a line break skipped.
        func argStart(_ from: Int) -> Int? {
            guard var point = backwardDelimiter(from, count: 1) else { return nil }
            point = min(point + 1, n)
            if point < n, text[point] == " " { point += 1 }
            if point < n, text[point] == "\n" { point = firstNonBlank(point + 1) }
            return point
        }
        if inner {
            guard let start = argStart(cursor), let end = forwardDelimiter(cursor, count: max(count, 1)) else { return nil }
            return start..<max(start, end)
        }
        // At the text's end evil-args reads the character after it, which fails in Doom.
        guard var end = forwardDelimiter(cursor, count: max(count, 1)), end < n else { return nil }
        let endsOnCloser = !at(end, delimiters)
        if !endsOnCloser {
            // evil-forward-arg from the delimiter: past it and one space, or onto the next line.
            end += 1
            if end < n, text[end] == " " { end += 1 }
            if end < n, text[end] == "\n" { end = firstNonBlank(end + 1) }
        }
        guard var start = argStart(cursor) else { return nil }
        if endsOnCloser {
            var back = start - 1
            while back >= 0, " \t\n".contains(text[back]) { back -= 1 }
            if !at(back, openers) {
                guard let delimiter = backwardDelimiter(start, count: 1) else { return nil }
                start = delimiter
            }
        }
        return start..<max(start, end)
    }

    /// Doom's ii / ai, ik / ak, ij / aj (evil-indent-plus): the lines around
    /// the cursor's at its indentation or deeper, blank lines included but not at the ends;
    /// k adds the line above with less indentation, j that line and the one below. a… adds
    /// the blank lines after (or, with none, before). A port of evil-indent-plus.el, whose
    /// odd edges it keeps.
    private func indentObject(inner: Bool, _ kind: Character) -> Range<Int>? {
        let lines = string.components(separatedBy: "\n")
        // forward-line can't go past the last line's start when the text ends in a line break.
        let end = text.last == "\n" || text.isEmpty ? lines.count - 1 : lines.count
        func line(_ i: Int) -> Int { min(i, lines.count - 1) }
        func blank(_ i: Int) -> Bool { lines[line(i)].allSatisfy { $0 == " " || $0 == "\t" } }
        func indent(_ i: Int) -> Int {
            // Doom's tab-width is 4.
            lines[line(i)].prefix { $0 == " " || $0 == "\t" }.reduce(0) { $1 == "\t" ? ($0 / 4 + 1) * 4 : $0 + 1 }
        }
        /// evil-indent-plus--seek: from `start`, while `holds`, by whole lines. `before`: the
        /// last line where it holds, else the first where it fails.
        func seek(_ start: Int, _ step: Int, before: Bool, skip: Bool, _ holds: (Int) -> Bool) -> Int {
            func move(_ i: Int) -> Int { step < 0 ? max(i - 1, 0) : min(i + 1, end) }
            var i = start, found = start
            if skip { i = move(i) }
            while i != (step < 0 ? 0 : end), holds(i) {
                if before { found = line(i) }
                i = move(i)
                if !before { found = line(i) }
            }
            return found
        }
        let here = lineIndex(cursor), base = indent(here)
        var first = seek(here, -1, before: true, skip: false) { blank($0) || indent($0) >= base }
        first = seek(first, 1, before: false, skip: false) { blank($0) || indent($0) > base }
        var last = seek(here, 1, before: true, skip: false) { blank($0) || indent($0) >= base }
        last = seek(last, -1, before: false, skip: false) { blank($0) }
        if kind == "k" || kind == "j" { first = seek(first, -1, before: false, skip: false) { blank($0) || indent($0) >= base } }
        if kind == "j" { last = seek(last, 1, before: false, skip: false) { blank($0) || indent($0) >= base } }
        if !inner {
            let after = seek(last, 1, before: true, skip: true) { blank($0) }
            if after == last { first = seek(first, -1, before: true, skip: true) { blank($0) } }
            last = after
        }
        return first..<(max(first, last) + 1)
    }

    /// An operator on ii, ik or ij. evil-indent-plus hands evil the lines' text without the
    /// last line break, so Doom's operators treat it oddly, and this keeps their results: d
    /// leaves an empty line (at the text's end it takes the line break before instead); c
    /// does that, then types on a new line above the empty one (below, at the end); y takes
    /// whole lines and goes to the first line's start; > and < keep the cursor's column; ys
    /// puts the pair on lines of its own, as ysip does here. Visual mode selects whole lines.
    private mutating func operateOnIndent(_ op: Operator, lines: Range<Int>) {
        let starts = lineStarts
        let start = starts[lines.lowerBound], end = lineEnd(starts[lines.upperBound - 1])
        let low = end == text.count && lines.lowerBound > 0 ? start - 1 : start
        switch op {
        case .yank:
            applyLines(.yank, lines.lowerBound, lines.upperBound - 1)
            cursor = start
        case .delete:
            apply(.delete, to: low..<end)
        case .surround:
            // As ysip here: the pair on lines of its own.
            applyLines(.surround, lines.lowerBound, lines.upperBound - 1)
        case .indent, .outdent:
            // Doom's > and < keep the cursor's column.
            let line = lineIndex(cursor), column = cursor - lineStart(cursor)
            applyLines(op, lines.lowerBound, lines.upperBound - 1)
            let lineStart = lineStarts[line]
            cursor = lineStart + min(column, max(lineEnd(lineStart) - lineStart - 1, 0))
        case .change:
            store(VimRegister(text: String(text[start..<end]) + "\n", linewise: true), yank: false)
            checkpoint(at: start)
            text.removeSubrange(low..<end)
            if low < start {
                text.append("\n")
                cursor = text.count
            } else {
                text.insert("\n", at: start)
                cursor = start
            }
            beginInsert()
        default:
            apply(op, to: start..<end)
        }
    }

    /// Doom's iq / aq (`+evil:inner-any-quote`, evil-textobj-anyblock over ' " ` and “ ”):
    /// each kind of quote gives a string, around the cursor or the next one after it, and
    /// the smallest wins, even one ahead of the cursor over one around it, as in Doom.
    /// aq takes the quotes alone, but evil adds the blanks after for ' and `, and for "
    /// when the cursor is on the opening quote. 2iq is aq without blanks, as evil's count 2.
    private func anyQuoteObject(inner: Bool, count: Int) -> Range<Int>? {
        var spans: [(open: Int, close: Int, quote: Character)] = []
        for quote in ["'", "\"", "`"] as [Character] {
            if let span = evilQuoteSpan(quote) { spans.append((span.0, span.1, quote)) }
        }
        if let open = enclosingOpen("“", "”", before: cursor) ?? (cursor < text.count && text[cursor] == "“" ? cursor : nil),
           let close = matchingClose("“", "”", from: open) {
            spans.append((open, close, "“"))
        }
        if spans.isEmpty, let open = (cursor..<text.count).first(where: { text[$0] == "“" }), let close = matchingClose("“", "”", from: open) {
            spans.append((open, close, "“"))
        }
        // A string before the cursor (none after it) loses to one around the cursor.
        if spans.contains(where: { $0.open <= cursor && cursor <= $0.close }) { spans.removeAll { $0.close < cursor } }
        guard let span = spans.min(by: { $0.close - $0.open < $1.close - $1.open }) else { return nil }
        if inner, count != 2 { return (span.open + 1)..<span.close }
        let quotesOnly = count == 2 || span.quote == "“" || (span.quote == "\"" && cursor != span.open)
        if quotesOnly { return span.open..<(span.close + 1) }
        let end = lineEnd(span.close)
        var high = span.close + 1
        while high < end, text[high] == " " || text[high] == "\t" { high += 1 }
        var low = span.open
        if high == span.close + 1 {
            let start = lineStart(span.open)
            while low > start, text[low - 1] == " " || text[low - 1] == "\t" { low -= 1 }
        }
        return low..<high
    }

    /// The string `quote` makes around the cursor, or the next one after it, as evil's
    /// evil-select-quote finds it in a plain buffer: strings are read from the top with
    /// backslash escapes, where `"` always makes strings and `quote` does too; with none
    /// after the cursor, the last one before it. Inside a "…" string, a ' or ` pair is found on vim's
    /// rule within that string.
    private func evilQuoteSpan(_ quote: Character) -> (Int, Int)? {
        var strings: [(open: Int, close: Int, quote: Character)] = []
        var open: (Int, Character)?
        var i = 0
        while i < text.count {
            let c = text[i]
            if c == "\\" {
                i += 2
                continue
            }
            if let (start, kind) = open {
                if c == kind {
                    strings.append((start, i, kind))
                    open = nil
                }
            } else if c == "\"" || c == quote {
                open = (i, c)
            }
            i += 1
        }
        if let around = strings.first(where: { $0.open <= cursor && cursor <= $0.close }) {
            if around.quote == quote { return (around.open, around.close) }
            // In a "…" string: the ' or ` pair on vim's rule, within the string.
            let quotes = ((around.open + 1)..<around.close).filter { i in
                text[i] == quote && lineIndex(i) == lineIndex(cursor) && text[lineStart(i)..<i].reversed().prefix { $0 == "\\" }.count % 2 == 0
            }
            if let at = quotes.firstIndex(of: cursor) {
                return at % 2 == 0 ? (at + 1 < quotes.count ? (quotes[at], quotes[at + 1]) : nil) : (quotes[at - 1], quotes[at])
            }
            if let before = quotes.last(where: { $0 < cursor }), let after = quotes.first(where: { $0 > cursor }) { return (before, after) }
            return nil
        }
        // The next string after the cursor, or with none, the last one before it.
        let own = strings.filter { $0.quote == quote }
        return (own.first(where: { $0.open > cursor }) ?? own.last).map { ($0.open, $0.close) }
    }

    // MARK: - vim's own cursor steps, for word motions and objects

    /// A position is a character, or a line's end: its "\n", or the text's end.
    private func vimIsLineEnd(_ i: Int) -> Bool { i >= text.count || text[i] == "\n" }

    /// vim's cls(): 0 for blanks and line ends.
    private func vimClass(_ i: Int, big: Bool) -> Int { vimIsLineEnd(i) ? 0 : characterClass(i, big: big) }

    /// vim's inc(): 0 within a line, 2 onto the line's end, 1 onto the next line, -1 at the text's end.
    private func vimInc(_ i: inout Int) -> Int {
        if !vimIsLineEnd(i) {
            i += 1
            return vimIsLineEnd(i) ? 2 : 0
        }
        guard i < text.count else { return -1 }
        i += 1
        return 1
    }

    /// vim's fwd_word(): `count` words forward. With `stopAtLineEnd` (vim's eol, used by
    /// operators) the last word stops at its line's end. False on the last line's end.
    private func vimForwardWord(_ i: inout Int, count: Int, big: Bool, stopAtLineEnd: Bool) -> Bool {
        let lastLineStart = lineStarts[lineStarts.count - 1]
        for left in (0..<max(count, 1)).reversed() {
            let sclass = vimClass(i, big: big)
            let lastLine = i >= lastLineStart
            var r = vimInc(&i)
            if r == -1 || (r >= 1 && lastLine) { return false }
            if r >= 1, stopAtLineEnd, left == 0 { return true }
            if sclass != 0 {
                while vimClass(i, big: big) == sclass {
                    r = vimInc(&i)
                    if r == -1 || (r >= 1 && stopAtLineEnd && left == 0) { return true }
                }
            }
            // Blanks, but an empty line is a word.
            while vimClass(i, big: big) == 0, !(vimIsLineEnd(i) && (i == 0 || text[i - 1] == "\n")) {
                r = vimInc(&i)
                if r == -1 || (r >= 1 && stopAtLineEnd && left == 0) { return true }
            }
        }
        return true
    }

    /// iw is the run of word, punctuation or blank characters under the
    /// cursor; aw adds the blanks after it (or before, at a line's end). A
    /// port of vim's current_word, so counts cross lines as vim's do: a line's
    /// end is a position (its "\n", or the text's end), and an empty line is a word.
    /// On failure `end` is where the search stopped, which is where vim leaves the cursor.
    private func wordObject(inner: Bool, big: Bool, count: Int) -> (start: Int, end: Int, inclusive: Bool, found: Bool) {
        // On the empty line after a final line break there is no character: the word is that
        // line break, as evil takes it in Doom (vim's port below would run backwards here). In
        // empty text it is empty, so ciw still types.
        guard cursor < text.count else { return (max(text.count - 1, 0), max(text.count - 1, 0), true, true) }
        func isEnd(_ i: Int) -> Bool { vimIsLineEnd(i) }
        func cls(_ i: Int) -> Int { vimClass(i, big: big) }
        func atLineStart(_ i: Int) -> Bool { i == 0 || text[i - 1] == "\n" }
        func inc(_ i: inout Int) -> Int { vimInc(&i) }
        func incl(_ i: inout Int) -> Int {
            let r = inc(&i)
            return r >= 1 && !atLineStart(i) ? inc(&i) : r
        }
        func dec(_ i: inout Int) -> Int {
            guard i > 0 else { return -1 }
            let crossed = atLineStart(i)
            i -= 1
            return crossed ? 1 : 0
        }
        func decl(_ i: inout Int) {
            if dec(&i) == 1, !atLineStart(i) { _ = dec(&i) }
        }
        func oneLeft(_ i: inout Int) -> Bool {
            guard !atLineStart(i) else { return false }
            i -= 1
            return true
        }
        func backInLine(_ i: inout Int) {
            let sclass = cls(i)
            while !atLineStart(i) {
                i -= 1
                if cls(i) != sclass {
                    i += 1
                    return
                }
            }
        }
        func forwardWord(_ i: inout Int) -> Bool { vimForwardWord(&i, count: 1, big: big, stopAtLineEnd: true) }
        // vim's end_word(1, big, stop: true, empty: true).
        func endWord(_ i: inout Int) -> Bool {
            let sclass = cls(i)
            if inc(&i) == -1 { return false }
            if cls(i) == sclass, sclass != 0 {
                while cls(i) == sclass { if inc(&i) == -1 { return false } }
            } else if sclass == 0 {
                while cls(i) == 0 {
                    if atLineStart(i), isEnd(i) { return true }
                    if inc(&i) == -1 { return false }
                }
                let word = cls(i)
                while cls(i) == word { if inc(&i) == -1 { return false } }
            }
            _ = dec(&i)
            return true
        }

        var i = cursor
        var inclusive = true
        var includeWhite = false
        backInLine(&i)
        var start = i
        if (cls(i) == 0) == !inner {
            guard endWord(&i) else { return (start, i, inclusive, false) }
        } else {
            _ = forwardWord(&i)
            if atLineStart(i) { decl(&i) } else { _ = oneLeft(&i) }
            includeWhite = !inner
        }
        var remaining = max(count, 1) - 1
        while remaining > 0 {
            inclusive = true
            guard incl(&i) != -1 else { return (start, i, inclusive, false) }
            if !inner != (cls(i) == 0) {
                if !forwardWord(&i), remaining > 1 { return (start, i, inclusive, false) }
                if !oneLeft(&i) { inclusive = false }
            } else {
                guard endWord(&i) else { return (start, i, inclusive, false) }
            }
            remaining -= 1
        }
        // aw with no blanks after takes the ones before, but not a line's indentation.
        if includeWhite, cls(i) != 0 || (atLineStart(i) && !inclusive) {
            var before = start
            if oneLeft(&before) {
                backInLine(&before)
                if cls(before) == 0, !atLineStart(before) { start = before }
            }
        }
        return (start, i, inclusive, true)
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
        if openAt == nil {
            // Not inside a pair: the next pair after the cursor, as vim and Neovim do. A count
            // takes the pair that many deep inside it (2a( on "x (a (b))" is "(b)"), else fails.
            var position = cursor
            for _ in 0..<max(count, 1) {
                guard let next = nextOpen(open, close, after: position) else { return nil }
                position = next
            }
            openAt = position
        } else {
            for _ in 1..<max(count, 1) {
                guard let current = openAt else { break }
                openAt = enclosingOpen(open, close, before: current)
            }
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

    /// The next open bracket after `position` that no close bracket in between ends first.
    private func nextOpen(_ open: Character, _ close: Character, after position: Int) -> Int? {
        var depth = 0
        for i in (position + 1)..<max(text.count, position + 1) {
            if text[i] == close { depth += 1 } else if text[i] == open {
                if depth == 0 { return i }
                depth -= 1
            }
        }
        return nil
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
        for block in 1..<blocks {
            guard last + 1 < starts.count else {
                // Out of paragraphs before the count is met: fail, as vim does. Only the blank
                // lines after a paragraph may be missing (ap takes the ones before instead).
                if inner || block < blocks - 1 || blank(line) { return nil }
                break
            }
            last = blockEnd(from: last + 1)
        }
        if !inner, !blank(line), blank(last) == false, first > 0 {
            // No blank lines after the paragraph: take the ones before it.
            while first > 0, blank(first - 1) { first -= 1 }
        }
        return first..<last + 1
    }

    // MARK: - Surround

    /// Marks before a typed function name in a replacement: ysiwf (name(…)) and ysiw⌃F ((name …)).
    static let functionCall: Character = "\u{1}", prefixCall: Character = "\u{2}"

    /// What a surround replacement puts around the text. ( [ { add a space
    /// inside, ) ] } and their aliases b r B don't; < or t takes a tag.
    static func surroundPair(_ replacement: String) -> (open: String, close: String)? {
        if replacement.first == functionCall { return (replacement.dropFirst() + "(", ")") }
        if replacement.first == prefixCall { return ("(" + replacement.dropFirst() + " ", ")") }
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
        case "f", "\u{6}":
            // embrace's function pairs: the nearest "(" around the cursor with a name right
            // before it (f: "name(") or a name and a space after it (⌃F: "(name ").
            func isName(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "-" }
            var position = cursor < text.count && text[cursor] == "(" ? cursor + 1 : cursor
            while let open = enclosingOpen("(", ")", before: position) {
                position = open
                guard let close = matchingClose("(", ")", from: open), close >= cursor else { continue }
                if target == "f" {
                    var start = open
                    while start > 0, isName(text[start - 1]) { start -= 1 }
                    if start < open { return (start..<open + 1, close..<close + 1) }
                } else {
                    var end = open + 1
                    while end < close, text[end] != " ", text[end] != "\n" { end += 1 }
                    if end > open + 1, end < close, text[end] == " " { return (open..<end + 1, close..<close + 1) }
                }
            }
            return nil
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
        let opening = Array(replacement?.open ?? "")
        text.replaceSubrange(close, with: Array(replacement?.close ?? ""))
        text.replaceSubrange(open, with: opening)
        // embrace (dsf, ds⌃F) keeps the cursor on its character; vim-surround goes to the start.
        cursor = "f\u{6}".contains(target) && replacement == nil ? max(cursor - open.count + opening.count, open.lowerBound) : open.lowerBound
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
        // ⌃H and ⌃J would read back as Backspace and a line break.
        case .ctrl("h"): "\u{F8F3}"
        case .ctrl("j"): "\u{F8F4}"
        case .ctrl(let c): Character(UnicodeScalar((c.asciiValue ?? 64) & 0x1f))
        case .escape: "\u{1b}"
        case .enter: "\r"
        case .backspace: "\u{8}"
        case .left: "\u{F702}"
        case .right: "\u{F703}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        // Private-use characters, so a macro holding ⌥J or ⌥K plays it back.
        case .alt(let c): c == "j" ? "\u{F8F0}" : "\u{F8F1}"
        case .command: "\u{F8F2}"
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
        case "\u{F8F0}": .alt("j")
        case "\u{F8F1}": .alt("k")
        case "\u{F8F2}": .command("R")
        case "\u{F8F3}": .ctrl("h")
        case "\u{F8F4}": .ctrl("j")
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
            // Still the block yanked here: it pastes as a block.
            if let yanked = registers["0"], yanked.blockwise, yanked.text == text { return yanked }
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
        if !text.isEmpty { noLines = false }
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
