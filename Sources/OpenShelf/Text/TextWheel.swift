import Foundation

/// A tool on the text wheel.
enum TextTool: CaseIterable, Hashable, Sendable {
    case trim
    case cleanUp
    case reindent
    case toMarkdown
    case dedent
    case indent
    case outdent
    case tabsSpaces
    case trimLines
    case straightenQuotes
    // Lines
    case sortAZ
    case sortNatural
    case sortByLength
    case reverseLines
    case shuffleLines
    case removeDuplicates
    case removeBlankLines
    case numberLines
    case markdownList
    case markdownTable
    case joinWithCommas
    case joinWithSpaces
    case splitAtCommas
    case splitAtSpaces
    case quoteLines
    case unquoteLines
    case addCommas
    // Case
    case upperCase
    case lowerCase
    case titleCase
    case sentenceCase
    case camelCase
    case pascalCase
    case snakeCase
    case kebabCase
    case constantCase
    // Fix
    case plainText
    case stripTracking
    case fixEncoding
    case stripANSI
    // Code
    case encodeURL, encodeBase64, encodeHTML, encodeJSON, encodeHex, encodeUnicode
    case decodeURL, decodeBase64, decodeHTML, decodeJSON, decodeHex, decodeUnicode
    case uuid, timestamp, loremIpsum, password
    case jwt
    // Format
    case wrapQuotes, wrapParentheses, wrapBrackets, wrapBraces, wrapCodeFence, wrapBlockQuote
    case markdownLink, alignTable, headingUp, headingDown
    case convertDate
    // Extract
    case extractLinks, extractEmails, extractNumbers, extractPhoneNumbers, extractDates
    // Reports: they say something about the text and leave it as it is.
    case count
    case md5
    case sha1
    case sha256

    var title: String {
        switch self {
        case .trim: "Trim"
        case .cleanUp: "Clean Up"
        case .reindent: "Re-indent"
        case .toMarkdown: "To Markdown"
        case .dedent: "Dedent"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .tabsSpaces: "Tabs ↔ Spaces"
        case .trimLines: "Trim Lines"
        case .straightenQuotes: "Straight Quotes"
        case .sortAZ: "Sort A–Z"
        case .sortNatural: "Sort Natural"
        case .sortByLength: "Sort by Length"
        case .reverseLines: "Reverse"
        case .shuffleLines: "Shuffle"
        case .removeDuplicates: "Remove Duplicates"
        case .removeBlankLines: "Remove Blank Lines"
        case .numberLines: "Number"
        case .markdownList: "Markdown List"
        case .markdownTable: "CSV → Table"
        case .joinWithCommas: "Join with Commas"
        case .joinWithSpaces: "Join with Spaces"
        case .splitAtCommas: "Split at Commas"
        case .splitAtSpaces: "Split at Spaces"
        case .quoteLines: "Quote"
        case .unquoteLines: "Unquote"
        case .addCommas: "Add Commas"
        case .upperCase: "UPPER"
        case .lowerCase: "lower"
        case .titleCase: "Title Case"
        case .sentenceCase: "Sentence case"
        case .camelCase: "camelCase"
        case .pascalCase: "PascalCase"
        case .snakeCase: "snake_case"
        case .kebabCase: "kebab-case"
        case .constantCase: "CONSTANT_CASE"
        case .plainText: "Plain Text"
        case .stripTracking: "Strip Tracking"
        case .fixEncoding: "Fix Encoding"
        case .stripANSI: "Strip ANSI"
        case .encodeURL, .decodeURL: "URL"
        case .encodeBase64, .decodeBase64: "Base64"
        case .encodeHTML, .decodeHTML: "HTML"
        case .encodeJSON, .decodeJSON: "JSON String"
        case .encodeHex, .decodeHex: "Hex"
        case .encodeUnicode, .decodeUnicode: "Unicode"
        case .uuid: "UUID"
        case .timestamp: "Timestamp"
        case .loremIpsum: "Lorem Ipsum"
        case .password: "Password"
        case .jwt: "JWT"
        case .wrapQuotes: "Quotes"
        case .wrapParentheses: "Parentheses"
        case .wrapBrackets: "Brackets"
        case .wrapBraces: "Braces"
        case .wrapCodeFence: "Code Fence"
        case .wrapBlockQuote: "Block Quote"
        case .markdownLink: "Link"
        case .alignTable: "Align Table"
        case .headingUp: "Heading Up"
        case .headingDown: "Heading Down"
        case .convertDate: "Dates"
        case .extractLinks: "Links"
        case .extractEmails: "Emails"
        case .extractNumbers: "Numbers"
        case .extractPhoneNumbers: "Phone Numbers"
        case .extractDates: "Dates"
        case .count: "Count"
        case .md5: "MD5"
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        }
    }

    var systemImage: String {
        switch self {
        case .trim: "scissors"
        case .cleanUp: "sparkles"
        case .reindent: "text.alignleft"
        case .toMarkdown: "number"
        case .dedent: "arrow.left.to.line"
        case .indent: "increase.indent"
        case .outdent: "decrease.indent"
        case .tabsSpaces: "arrow.left.arrow.right"
        case .trimLines: "line.3.horizontal"
        case .straightenQuotes: "quote.opening"
        case .sortAZ: "arrow.up.arrow.down"
        case .sortNatural: "textformat.123"
        case .sortByLength: "ruler"
        case .reverseLines: "arrow.uturn.up"
        case .shuffleLines: "shuffle"
        case .removeDuplicates: "square.on.square"
        case .removeBlankLines: "text.badge.minus"
        case .numberLines: "list.number"
        case .markdownList: "list.bullet"
        case .markdownTable: "tablecells"
        case .joinWithCommas, .joinWithSpaces: "arrow.right.and.line.vertical.and.arrow.left"
        case .splitAtCommas, .splitAtSpaces: "arrow.left.and.line.vertical.and.arrow.right"
        case .quoteLines: "quote.closing"
        case .unquoteLines: "quote.bubble"
        case .addCommas: "text.append"
        case .upperCase: "textformat.size.larger"
        case .lowerCase: "textformat.size.smaller"
        case .titleCase: "textformat"
        case .sentenceCase: "text.alignleft"
        case .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase: "chevron.left.forwardslash.chevron.right"
        case .plainText: "doc.plaintext"
        case .stripTracking: "link"
        case .fixEncoding: "character"
        case .stripANSI: "paintbrush"
        case .encodeURL, .encodeBase64, .encodeHTML, .encodeJSON, .encodeHex, .encodeUnicode: "arrowshape.right"
        case .decodeURL, .decodeBase64, .decodeHTML, .decodeJSON, .decodeHex, .decodeUnicode: "arrowshape.left"
        case .uuid: "number"
        case .timestamp: "clock"
        case .loremIpsum: "text.quote"
        case .password: "key"
        case .jwt: "key.horizontal"
        case .wrapQuotes: "quote.opening"
        case .wrapParentheses: "parentheses"
        case .wrapBrackets: "chevron.left.square"
        case .wrapBraces: "curlybraces"
        case .wrapCodeFence: "chevron.left.forwardslash.chevron.right"
        case .wrapBlockQuote: "text.quote"
        case .markdownLink: "link.badge.plus"
        case .alignTable: "tablecells"
        case .headingUp: "textformat.size.larger"
        case .headingDown: "textformat.size.smaller"
        case .convertDate: "calendar.badge.clock"
        case .extractLinks: "link"
        case .extractEmails: "at"
        case .extractNumbers: "number"
        case .extractPhoneNumbers: "phone"
        case .extractDates: "calendar"
        case .count: "sum"
        case .md5, .sha1, .sha256: "number.square"
        }
    }

    /// Tools done in memory that return new text, with no file and no external process.
    /// Link also needs the clipboard, so the controller runs it.
    var isPureSwift: Bool { ![.reindent, .toMarkdown, .markdownLink].contains(self) && !isReport }

    /// Count, the hashes and JWT say something about the text and don't change it.
    var isReport: Bool { [.count, .md5, .sha1, .sha256, .jwt].contains(self) }

    /// The format an Encode or Decode tool works in, and which way.
    var codeFormat: (format: CodeTransforms.Format, encodes: Bool)? {
        switch self {
        case .encodeURL: (.url, true)
        case .encodeBase64: (.base64, true)
        case .encodeHTML: (.html, true)
        case .encodeJSON: (.jsonString, true)
        case .encodeHex: (.hex, true)
        case .encodeUnicode: (.unicode, true)
        case .decodeURL: (.url, false)
        case .decodeBase64: (.base64, false)
        case .decodeHTML: (.html, false)
        case .decodeJSON: (.jsonString, false)
        case .decodeHex: (.hex, false)
        case .decodeUnicode: (.unicode, false)
        default: nil
        }
    }

    /// The digest a hash tool takes.
    var digest: TextInfo.Digest? {
        switch self {
        case .md5: .md5
        case .sha1: .sha1
        case .sha256: .sha256
        default: nil
        }
    }

    /// Runs a pure-Swift tool; nil for the ones that need a converter.
    func apply(to text: String) -> String? {
        switch self {
        case .trim: TextTransforms.trim(text)
        case .cleanUp: TextTransforms.cleanUp(text)
        case .dedent: TextTransforms.dedent(text)
        case .indent: TextTransforms.indent(text)
        case .outdent: TextTransforms.outdent(text)
        case .tabsSpaces:
            Self.indentsWithTabs(text) ? TextTransforms.tabsToSpaces(text) : TextTransforms.spacesToTabs(text)
        case .trimLines: TextTransforms.trimLines(text)
        case .straightenQuotes: TextTransforms.straightenQuotes(text)
        case .sortAZ: LineTransforms.sortAZ(text)
        case .sortNatural: LineTransforms.sortNatural(text)
        case .sortByLength: LineTransforms.sortByLength(text)
        case .reverseLines: LineTransforms.reverse(text)
        case .shuffleLines: LineTransforms.shuffle(text)
        case .removeDuplicates: LineTransforms.removeDuplicates(text)
        case .removeBlankLines: LineTransforms.removeBlankLines(text)
        case .numberLines: LineTransforms.number(text)
        case .markdownList: LineTransforms.markdownList(text)
        case .markdownTable: LineTransforms.markdownTable(text)
        case .joinWithCommas: LineTransforms.join(text, with: ", ")
        case .joinWithSpaces: LineTransforms.join(text, with: " ")
        case .splitAtCommas: LineTransforms.split(text, at: ",")
        case .splitAtSpaces: LineTransforms.splitAtSpaces(text)
        case .quoteLines: LineTransforms.quote(text)
        case .unquoteLines: LineTransforms.unquote(text)
        case .addCommas: LineTransforms.addCommas(text)
        case .upperCase: CaseTransforms.upper(text)
        case .lowerCase: CaseTransforms.lower(text)
        case .titleCase: CaseTransforms.title(text)
        case .sentenceCase: CaseTransforms.sentence(text)
        case .camelCase: CaseTransforms.camel(text)
        case .pascalCase: CaseTransforms.pascal(text)
        case .snakeCase: CaseTransforms.snake(text)
        case .kebabCase: CaseTransforms.kebab(text)
        case .constantCase: CaseTransforms.constant(text)
        case .plainText: FixTransforms.plainText(text)
        case .stripTracking: FixTransforms.stripTracking(text)
        case .fixEncoding: FixTransforms.fixEncoding(text)
        case .stripANSI: FixTransforms.stripANSI(text)
        case .encodeURL, .encodeBase64, .encodeHTML, .encodeJSON, .encodeHex, .encodeUnicode,
             .decodeURL, .decodeBase64, .decodeHTML, .decodeJSON, .decodeHex, .decodeUnicode:
            codeFormat.map { $0.encodes ? CodeTransforms.encode(text, as: $0.format) : CodeTransforms.decode(text, from: $0.format) }
        // Generators replace the selection with something new.
        case .uuid: CodeTransforms.uuid()
        case .timestamp: CodeTransforms.timestamp()
        case .loremIpsum: CodeTransforms.loremIpsum
        case .password: CodeTransforms.password()
        case .wrapQuotes: FormatTransforms.wrap(text, in: .quotes)
        case .wrapParentheses: FormatTransforms.wrap(text, in: .parentheses)
        case .wrapBrackets: FormatTransforms.wrap(text, in: .brackets)
        case .wrapBraces: FormatTransforms.wrap(text, in: .braces)
        case .wrapCodeFence: FormatTransforms.wrap(text, in: .codeFence)
        case .wrapBlockQuote: FormatTransforms.wrap(text, in: .blockQuote)
        case .alignTable: FormatTransforms.alignTable(text)
        case .headingUp: FormatTransforms.heading(text, up: true)
        case .headingDown: FormatTransforms.heading(text, up: false)
        case .convertDate: FormatTransforms.convertDate(text)
        case .markdownLink: nil
        case .extractLinks: ExtractTransforms.extract(.links, from: text)
        case .extractEmails: ExtractTransforms.extract(.emails, from: text)
        case .extractNumbers: ExtractTransforms.extract(.numbers, from: text)
        case .extractPhoneNumbers: ExtractTransforms.extract(.phoneNumbers, from: text)
        case .extractDates: ExtractTransforms.extract(.dates, from: text)
        case .reindent, .toMarkdown, .count, .md5, .sha1, .sha256, .jwt: nil
        }
    }

    /// Whether any line is indented with a tab, which decides the direction of Tabs ↔ Spaces.
    static func indentsWithTabs(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { $0.prefix { $0 == " " || $0 == "\t" }.contains("\t") }
    }
}

/// The sub-wheels a text wheel wedge can open. Each fits on one wheel, so
/// a long group is split into smaller ones rather than paged.
enum TextGroup: CaseIterable, Hashable, Sendable {
    case convert
    case more
    case lines
    /// Less common orders, under Lines.
    case order
    case joinSplit
    case lists
    case textCase
    /// The identifier cases, under Case.
    case codeCase
    case indentation
    case fix
    case format
    case code
    case hash
    case wrap
    case markdown
    case encode
    case decode
    case generate
    case extract

    var title: String {
        switch self {
        case .convert: "Convert"
        case .more: "More"
        case .lines: "Lines"
        case .order: "Order"
        case .joinSplit: "Join & Split"
        case .lists: "Lists"
        case .textCase: "Case"
        case .codeCase: "Code Case"
        case .indentation: "Indent"
        case .fix: "Fix"
        case .format: "Format"
        case .code: "Code"
        case .hash: "Hash"
        case .wrap: "Wrap"
        case .markdown: "Markdown"
        case .encode: "Encode"
        case .decode: "Decode"
        case .generate: "Generate"
        case .extract: "Extract"
        }
    }

    var systemImage: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .more: "ellipsis.circle"
        case .lines: "list.bullet"
        case .order: "arrow.up.arrow.down"
        case .joinSplit: "arrow.left.and.right.text.vertical"
        case .lists: "list.number"
        case .textCase: "textformat"
        case .codeCase: "chevron.left.forwardslash.chevron.right"
        case .indentation: "increase.indent"
        case .fix: "wand.and.stars"
        case .format: "paragraphsign"
        case .code: "curlybraces"
        case .hash: "number.square"
        case .wrap: "parentheses"
        case .markdown: "number"
        case .encode: "arrowshape.right"
        case .decode: "arrowshape.left"
        case .generate: "sparkle"
        case .extract: "text.magnifyingglass"
        }
    }

    /// Where Back goes: the wheel this group opens from (nil is the first wheel).
    var parent: TextGroup? {
        switch self {
        case .convert, .more: nil
        case .lines, .textCase, .fix, .format, .code, .extract: .more
        case .indentation: .format
        case .hash, .encode, .decode, .generate: .code
        case .wrap, .markdown: .format
        case .order, .joinSplit, .lists: .lines
        case .codeCase: .textCase
        }
    }

    /// The wedges of this wheel before Back, in order. Convert's depend on
    /// the selection, so `TextWheel` builds them.
    var wedges: [TextCommand] {
        switch self {
        case .convert: []
        // More ▸ as David approved it (2026-11-18); Fix, Format, Code and Extract fill up as their tools are built.
        case .more: [.open(.lines), .open(.textCase), .open(.fix), .open(.format), .open(.code), .open(.extract)]
        case .fix: [.tool(.trimLines), .tool(.straightenQuotes), .tool(.plainText), .tool(.stripTracking), .tool(.fixEncoding), .tool(.stripANSI)]
        case .format: [.open(.indentation), .open(.wrap), .open(.markdown), .tool(.convertDate)]
        case .wrap: [.tool(.wrapQuotes), .tool(.wrapParentheses), .tool(.wrapBrackets), .tool(.wrapBraces), .tool(.wrapCodeFence), .tool(.wrapBlockQuote)]
        case .markdown: [.tool(.markdownLink), .tool(.alignTable), .tool(.headingUp), .tool(.headingDown)]
        case .code: [.open(.encode), .open(.decode), .open(.hash), .open(.generate), .tool(.jwt)]
        case .encode: [.tool(.encodeURL), .tool(.encodeBase64), .tool(.encodeHTML), .tool(.encodeJSON), .tool(.encodeHex), .tool(.encodeUnicode)]
        case .decode: [.tool(.decodeURL), .tool(.decodeBase64), .tool(.decodeHTML), .tool(.decodeJSON), .tool(.decodeHex), .tool(.decodeUnicode)]
        case .generate: [.tool(.uuid), .tool(.timestamp), .tool(.loremIpsum), .tool(.password)]
        case .hash: [.tool(.md5), .tool(.sha1), .tool(.sha256)]
        case .extract: [.tool(.extractLinks), .tool(.extractEmails), .tool(.extractNumbers), .tool(.extractPhoneNumbers), .tool(.extractDates), .tool(.count)]
        case .lines: [.tool(.sortAZ), .tool(.removeDuplicates), .tool(.removeBlankLines), .open(.order), .open(.joinSplit), .open(.lists)]
        case .order: [.tool(.sortNatural), .tool(.sortByLength), .tool(.reverseLines), .tool(.shuffleLines)]
        case .joinSplit: [.tool(.joinWithCommas), .tool(.joinWithSpaces), .tool(.splitAtCommas), .tool(.splitAtSpaces)]
        case .lists: [.tool(.numberLines), .tool(.markdownList), .tool(.markdownTable), .tool(.quoteLines), .tool(.unquoteLines), .tool(.addCommas)]
        case .textCase: [.tool(.upperCase), .tool(.lowerCase), .tool(.titleCase), .tool(.sentenceCase), .open(.codeCase)]
        case .codeCase: [.tool(.camelCase), .tool(.pascalCase), .tool(.snakeCase), .tool(.kebabCase), .tool(.constantCase)]
        case .indentation: [.tool(.dedent), .tool(.indent), .tool(.outdent), .tool(.tabsSpaces)]
        }
    }
}

/// What a wedge on the text wheel does.
enum TextCommand: Hashable, Sendable {
    case tool(TextTool)
    case convert(DataTextFormat)
    case open(TextGroup)
    /// Back from a sub-wheel to the wheel it opened from (nil: the first wheel).
    case back(TextGroup?)
    /// Puts the original back over what OpenShelf wrote (⌥ copies it instead).
    case undo
    /// Opens the selection in the Edit window, with vim keys.
    case edit
}

extension TextCommand {
    /// The first words of the confirmation: "Trimmed and copied".
    var doneTitle: String {
        switch self {
        case .tool(let tool):
            switch tool {
            case .trim: "Trimmed"
            case .cleanUp: "Cleaned up"
            case .reindent: "Re-indented"
            case .toMarkdown: "Converted to Markdown"
            case .dedent: "Dedented"
            case .indent: "Indented"
            case .outdent: "Outdented"
            case .tabsSpaces: "Converted indentation"
            case .trimLines: "Trimmed lines"
            case .straightenQuotes: "Straightened quotes"
            case .sortAZ, .sortNatural, .sortByLength: "Sorted"
            case .reverseLines: "Reversed"
            case .shuffleLines: "Shuffled"
            case .removeDuplicates: "Removed duplicates"
            case .removeBlankLines: "Removed blank lines"
            case .numberLines: "Numbered"
            case .markdownList: "Made a list"
            case .markdownTable: "Made a table"
            case .joinWithCommas, .joinWithSpaces: "Joined"
            case .splitAtCommas, .splitAtSpaces: "Split"
            case .quoteLines: "Quoted"
            case .unquoteLines: "Unquoted"
            case .addCommas: "Added commas"
            case .upperCase, .lowerCase, .titleCase, .sentenceCase, .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase:
                "Changed to \(tool.title)"
            case .plainText: "Made plain text"
            case .stripTracking: "Stripped tracking"
            case .fixEncoding: "Fixed encoding"
            case .stripANSI: "Stripped colour codes"
            case .encodeURL, .encodeBase64, .encodeHTML, .encodeJSON, .encodeHex, .encodeUnicode: "Encoded as \(tool.title)"
            case .decodeURL, .decodeBase64, .decodeHTML, .decodeJSON, .decodeHex, .decodeUnicode: "Decoded \(tool.title)"
            case .uuid: "Made a UUID"
            case .timestamp: "Made a timestamp"
            case .loremIpsum: "Made placeholder text"
            case .password: "Made a password"
            case .jwt: "JWT read and copied"
            case .wrapQuotes, .wrapParentheses, .wrapBrackets, .wrapBraces, .wrapCodeFence, .wrapBlockQuote: "Wrapped in \(tool.title.lowercased())"
            case .markdownLink: "Made a link"
            case .alignTable: "Aligned the table"
            case .headingUp, .headingDown: "Changed headings"
            case .convertDate: "Converted the date"
            case .extractLinks, .extractEmails, .extractNumbers, .extractPhoneNumbers, .extractDates: "Extracted \(tool.title.lowercased())"
            case .count: "Counted"
            case .md5, .sha1, .sha256: "\(tool.title) copied"
            }
        case .convert(let format): "Converted to \(format.title)"
        case .undo: "Original"
        case .edit: "Edited"
        case .open, .back: ""
        }
    }
}

/// What is known about a selection when its wheel is built.
struct TextContext: Equatable {
    var dataFormat: DataTextFormat?
    var codeExtension: String?
    /// The selection may have an HTML or RTF version for To Markdown to read.
    var hasRichText: Bool
    var canUndo: Bool

    init(text: String, hasRichText: Bool, canUndo: Bool) {
        dataFormat = TextSniffer.dataFormat(of: text)
        codeExtension = TextSniffer.codeExtension(for: text)
        self.hasRichText = hasRichText
        self.canUndo = canUndo
    }
}

/// The wedges of the text wheel and its sub-wheels. A wheel shows 7 wedges
/// before it pages, so each list here stays at 7 or fewer.
enum TextWheel {
    /// The wheel's name. Text taken from the clipboard shows its first line,
    /// so it's clear what the tool will act on.
    static func title(for text: String, from source: TextReader) -> String {
        guard source == .recentClipboard else { return "Text" }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let short = firstLine.count > 24 ? String(firstLine.prefix(23)) + "…" : firstLine
        return "Copied: \(short)"
    }

    static func items(for context: TextContext, group: TextGroup? = nil) -> [WheelItem] {
        switch group {
        case nil:
            var commands: [TextCommand] = []
            if context.canUndo { commands.append(.undo) }
            commands += [.edit, .tool(.trim), .tool(.cleanUp)]
            if context.codeExtension != nil { commands.append(.tool(.reindent)) }
            if context.dataFormat != nil { commands.append(.open(.convert)) }
            // Formatted prose, not data or code, is what To Markdown is for.
            if context.hasRichText, context.dataFormat == nil, context.codeExtension == nil { commands.append(.tool(.toMarkdown)) }
            commands.append(.open(.more))
            return commands.map(WheelItem.text)
        case .convert:
            let targets = DataTextFormat.allCases.filter { $0 != context.dataFormat }
            return targets.map { WheelItem.text(.convert($0)) } + [WheelItem.text(.back(nil))]
        case let group?:
            return (group.wedges + [.back(group.parent)]).map(WheelItem.text)
        }
    }
}

extension TextWheel {
    /// Every tool reachable from `group`'s wheel, through its sub-wheels, for
    /// search. Sub-wheel and Back wedges aren't results; their tools are.
    static func searchCandidates(for context: TextContext, from group: TextGroup? = nil, path: [String] = []) -> [WheelSearchCandidate] {
        items(for: context, group: group).flatMap { item -> [WheelSearchCandidate] in
            guard case .text(let command) = item.command else { return [] }
            switch command {
            // More is only a way in; the path starts at the group under it.
            case .open(let child): return searchCandidates(for: context, from: child, path: child == .more ? path : path + [child.title])
            case .back: return []
            case .tool, .convert, .undo, .edit: return [WheelSearchCandidate(item: item, path: path)]
            }
        }
    }
}

extension WheelItem {
    static func text(_ command: TextCommand) -> WheelItem {
        switch command {
        case .tool(let tool):
            WheelItem(command: .text(command), title: tool.title, systemImage: tool.systemImage)
        case .convert(let format):
            WheelItem(command: .text(command), title: format.title, systemImage: nil)
        case .open(let group):
            WheelItem(command: .text(command), title: "\(group.title) ▸", systemImage: group.systemImage)
        case .back:
            WheelItem(command: .text(command), title: "Back", systemImage: "chevron.backward")
        case .undo:
            WheelItem(command: .text(command), title: "Undo", systemImage: "arrow.uturn.backward")
        case .edit:
            WheelItem(command: .text(command), title: "Edit", systemImage: "character.cursor.ibeam")
        }
    }
}
