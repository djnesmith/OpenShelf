import AppKit

/// Quick filing (MAIL-PLAN slice C): a picker of Mail's mailboxes; type part of a name,
/// Return moves the selected messages there. Mailboxes and the move go through Mail's
/// AppleScript. Recently used mailboxes come first.
@MainActor
enum MailFiling {
    struct Mailbox: Equatable, Hashable, Sendable {
        /// The account's name; empty for On My Mac.
        var account: String
        /// "Projects/2026" for a mailbox inside another.
        var path: String

        /// Each folder's own name, top first.
        var chain: [String] { MailFiling.chain(of: path) }
        /// The path as Mail shows it, slashes in names unescaped.
        var shown: String { chain.joined(separator: "/") }
        var display: String { account.isEmpty ? shown : "\(shown) — \(account)" }
    }

    /// A path keeps "/" between folders; a "/" or "\\" inside a folder's own name is
    /// stored with a backslash before it, so a name like "a/b" stays one folder.
    nonisolated static func joinPath(_ names: [String]) -> String {
        names.map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "/", with: "\\/") }.joined(separator: "/")
    }

    nonisolated static func chain(of path: String) -> [String] {
        var names: [String] = [], current = "", escaped = false
        for character in path {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "/" { names.append(current); current = "" }
            else { current.append(character) }
        }
        names.append(current)
        return names.filter { !$0.isEmpty }
    }

    static let recentKey = "MailFilingRecent"
    static let recentLimit = 10

    /// How well `query` matches `mailbox`, or nil for no match: every typed character in
    /// order (case ignored), scored higher for matches at the start of a word, in a row,
    /// and in the mailbox's own name rather than its parents'.
    static func score(_ query: String, _ mailbox: Mailbox) -> Int? {
        let typed = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !typed.isEmpty else { return 0 }
        let name = Array(mailbox.shown.lowercased())
        let leafStart = name.count - (mailbox.chain.last?.lowercased().count ?? 0)
        var score = 0
        var index = 0
        var previous = -2
        for character in typed {
            guard let found = name[index...].firstIndex(of: character) else { return nil }
            let wordStart = found == 0 || !name[found - 1].isLetter && !name[found - 1].isNumber
            score += 1 + (wordStart ? 8 : 0) + (found == previous + 1 ? 4 : 0) + (found >= leafStart ? 2 : 0)
            previous = found
            index = found + 1
        }
        // Shorter names win a tie: "Bills" over "Bills/Old".
        return score * 100 - name.count
    }

    /// The mailboxes matching `query`, best first; recent ones ahead of equal matches. With
    /// nothing typed, the recent ones then the rest in order.
    static func rank(_ query: String, in mailboxes: [Mailbox], recent: [Mailbox], limit: Int = 8) -> [Mailbox] {
        let scored = mailboxes.compactMap { box in score(query, box).map { (box, $0) } }
        func recency(_ box: Mailbox) -> Int { recent.firstIndex(of: box).map { recent.count - $0 } ?? 0 }
        return scored.sorted { a, b in
            if query.isEmpty || a.1 == b.1 { return recency(a.0) != recency(b.0) ? recency(a.0) > recency(b.0) : a.0.display < b.0.display }
            return a.1 > b.1
        }.prefix(limit).map(\.0)
    }

    /// `chosen` first in the recent list, which keeps `recentLimit`.
    static func remember(_ chosen: Mailbox, in recent: [Mailbox]) -> [Mailbox] {
        Array(([chosen] + recent.filter { $0 != chosen }).prefix(recentLimit))
    }

    static func loadRecent(_ defaults: UserDefaults = .standard) -> [Mailbox] {
        (defaults.array(forKey: recentKey) as? [[String]] ?? []).compactMap { $0.count == 2 ? Mailbox(account: $0[0], path: $0[1]) : nil }
    }

    static func saveRecent(_ recent: [Mailbox], _ defaults: UserDefaults = .standard) {
        defaults.set(recent.map { [$0.account, $0.path] }, forKey: recentKey)
    }

    /// What a move came to, from Mail: how many of the messages are in the destination and
    /// how many are still in their source (2026-11-20: a move back to the Inbox reported
    /// success and left the message in both).
    enum MoveOutcome: Equatable {
        case moved
        /// In the destination and still in the source.
        case copied
        case notMoved
        /// Some moved, some didn't.
        case partial
    }

    /// What the move script read back from Mail, message by message.
    enum MoveResult: Equatable {
        /// The folder's name didn't resolve: the error, and the level (1 is the top) that failed.
        case folderNotFound(error: Int, level: Int, of: Int)
        case nothingSelected
        /// Per message, read back from Mail after the move. `fellBack` counts messages whose
        /// mailbox couldn't be set, so the move command ran instead; `source` is the first
        /// message's folder name, for the toast only (never logged).
        case counted(moved: Int, copied: Int, unchanged: Int, neither: Int, fellBack: Int, source: String)
        case unreadable

        var logLine: String {
            switch self {
            case .folderNotFound(let error, let level, let depth): "the folder didn't resolve at level \(level) of \(depth) (error \(error)); nothing moved"
            case .nothingSelected: "nothing selected"
            case .counted(let moved, let copied, let unchanged, let neither, let fellBack, _): "moved \(moved), copied \(copied), unchanged \(unchanged), in neither folder \(neither); move command used for \(fellBack)"
            case .unreadable: "Mail's answer couldn't be read; nothing claimed"
            }
        }

        /// The toast: only what Mail showed.
        @MainActor func report(to mailbox: Mailbox) -> MoveReport {
            switch self {
            case .folderNotFound: return MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Can't find that folder in Mail")
            case .nothingSelected: return MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Select a message in Mail first")
            case .unreadable: return MoveReport(outcome: .notMoved, title: "Not sure what moved", subtitle: "Check the folder in Mail")
            case .counted(let moved, let copied, let unchanged, let neither, _, let source):
                let total = moved + copied + unchanged + neither
                if moved == total, total > 0 { return MailFiling.report(.moved, total: total, to: mailbox) }
                if copied == total { return MailFiling.report(.copied, total: total, to: mailbox, source: source) }
                if moved + copied == 0, neither == 0 { return MailFiling.report(.notMoved, total: total, to: mailbox, problem: "Mail left \(total == 1 ? "it" : "them") where \(total == 1 ? "it was" : "they were")") }
                var parts = ["\(moved) moved"]
                if copied > 0 { parts.append("\(copied) copied") }
                if unchanged > 0 { parts.append("\(unchanged) left") }
                if neither > 0 { parts.append("\(neither) not found in either folder") }
                return MoveReport(outcome: .partial, title: "Partly moved to \(mailbox.shown)", subtitle: parts.joined(separator: ", "))
            }
        }
    }

    static func moveResult(_ text: String) -> MoveResult {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t").map(String.init)
        switch parts.first {
        case "#NOFOLDER"? where parts.count == 4:
            return .folderNotFound(error: Int(parts[1]) ?? 0, level: Int(parts[2]) ?? 0, of: Int(parts[3]) ?? 0)
        case "#NOFOLDER"?: return .folderNotFound(error: 0, level: 0, of: 0)
        case "#NONE"?: return .nothingSelected
        case "#RESULT"? where parts.count >= 6:
            let numbers = parts[1...5].compactMap { Int($0) }
            guard numbers.count == 5 else { return .unreadable }
            let source = parts.dropFirst(6).joined(separator: "\t")
            return .counted(moved: numbers[0], copied: numbers[1], unchanged: numbers[2], neither: numbers[3], fellBack: numbers[4], source: source)
        default: return .unreadable
        }
    }

    struct MoveReport: Equatable {
        var outcome: MoveOutcome
        var title: String
        var subtitle: String
    }

    /// What the toast says: only what Mail shows.
    static func report(_ outcome: MoveOutcome, total: Int, to mailbox: Mailbox, problem: String? = nil, source: String = "") -> MoveReport {
        let count = total == 1 ? "1 message" : "\(total) messages"
        switch outcome {
        case .moved: return MoveReport(outcome: outcome, title: "Moved to \(mailbox.shown)", subtitle: count)
        case .copied: return MoveReport(outcome: outcome, title: "Copied to \(mailbox.shown)", subtitle: "\(count); still in \(folderName(source))")
        case .partial: return MoveReport(outcome: outcome, title: "Partly moved to \(mailbox.shown)", subtitle: "Check \(count) in Mail")
        case .notMoved: return MoveReport(outcome: outcome, title: "Not moved", subtitle: problem ?? "Mail didn't move it")
        }
    }

    /// Mail names Gmail's and IMAP's inbox "INBOX"; the toast says "the Inbox".
    static func folderName(_ source: String) -> String {
        if source.isEmpty { return "the folder it was in" }
        return source.uppercased() == "INBOX" ? "the Inbox" : source
    }

    static func moveOutcome(total: Int, inSource: Int, inDestination: Int) -> MoveOutcome {
        guard total > 0, inDestination > 0 else { return .notMoved }
        if inDestination >= total, inSource == 0 { return .moved }
        if inSource > 0, inDestination >= total { return .copied }
        return .partial
    }




    /// Paths from the bulk listing's lines, in Mail's order; nil when Mail's answer didn't
    /// line up (the full walk is used then).
    static func bulkPaths(_ lines: [String]) -> [String]? {
        if lines.contains("#MISALIGNED") { return nil }
        var level1: [String] = [], level2: [(Int, String)] = [], level3: [(Int, Int, String)] = []
        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch parts.first {
            case "#L1" where parts.count == 2: level1.append(parts[1])
            case "#L2" where parts.count == 3: guard let i = Int(parts[1]) else { return nil }; level2.append((i, parts[2]))
            case "#L3" where parts.count == 4: guard let i = Int(parts[1]), let j = Int(parts[2]) else { return nil }; level3.append((i, j, parts[3]))
            default: continue
            }
        }
        var paths: [String] = []
        for (i1, top) in level1.enumerated() {
            paths.append(joinPath([top]))
            let kids = level2.filter { $0.0 == i1 + 1 }.map(\.1)
            for (i2, kid) in kids.enumerated() {
                paths.append(joinPath([top, kid]))
                for grandkid in level3.filter({ $0.0 == i1 + 1 && $0.1 == i2 + 1 }).map(\.2) { paths.append(joinPath([top, kid, grandkid])) }
            }
        }
        // A level 2 or 3 entry pointing past its parents means the answer didn't line up.
        if level2.contains(where: { $0.0 < 1 || $0.0 > level1.count }) { return nil }
        return paths
    }

    /// Which mailboxes `v` offers (David, 2026-11-20: "v for work account should just
    /// be its folders, v for gmail only its folders"): the selected messages' one account.
    enum Scope: Equatable {
        case account(String)
        /// Messages from more than one account: a move would copy across accounts.
        case mixed
        case nothingSelected
    }

    /// One account name per line, each line ending in a line feed; an empty line is On My
    /// Mac, so empty lines are kept.
    static func accountLines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return text.isEmpty ? [] : lines
    }

    static func scope(of accounts: [String]) -> Scope {
        let unique = Set(accounts)
        guard !accounts.isEmpty else { return .nothingSelected }
        guard unique.count == 1, let account = unique.first else { return .mixed }
        return .account(account)
    }

    /// The picker's list: the account's own mailboxes first, then On My Mac's (a local
    /// folder is a fair target); for an On My Mac selection, On My Mac's alone.
    static func pickerList(account: String, own: [Mailbox], local: [Mailbox]) -> [Mailbox] {
        account.isEmpty ? local : own + local.filter { $0.account.isEmpty }
    }

    /// Mailbox lists by account, kept across launches so the picker opens at once.
    static let cacheKey = "MailFilingMailboxesByAccount"

    static func loadCache(_ defaults: UserDefaults = .standard) -> [String: [Mailbox]] {
        let stored = defaults.dictionary(forKey: cacheKey) as? [String: [String]] ?? [:]
        return stored.mapValues { paths in paths.map { Mailbox(account: "", path: $0) } }
            .reduce(into: [:]) { result, entry in result[entry.key] = entry.value.map { Mailbox(account: entry.key, path: $0.path) } }
    }

    static func saveCache(_ cache: [String: [Mailbox]], _ defaults: UserDefaults = .standard) {
        defaults.set(cache.mapValues { $0.map(\.path) }, forKey: cacheKey)
    }

    /// Which opening of the picker a listing belongs to; an answer for an older one is dropped.
    static var opening = 0

    /// Per account, how many mailboxes were read and how many skipped with which error:
    /// "On My Mac 2 read; account 2 14 read, 1 skipped (-1700); account 1 off". Account
    /// names stay out of the log.
    static func listingSummary(_ lines: [String]) -> String {
        var parts: [String] = [], read = 0, skips: [String] = []
        for line in lines {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2 else { continue }
            switch fields[0] {
            case "#SKIP": skips.append(String(fields[1].split(separator: " ").last ?? "?"))
            case "#DONE":
                parts.append("\(fields[1]) \(read) read" + (skips.isEmpty ? "" : ", \(skips.count) skipped (\(Set(skips).sorted().joined(separator: ", ")))"))
                read = 0
                skips = []
            case "#OFF": parts.append("\(fields[1]) off")
            case "#ERR": read = 0; skips = []
            case "#STEP": continue
            case "#FAIL": skips.append(String(fields[1].split(separator: " ").dropFirst(2).first ?? "?"))
            default: read += 1
            }
        }
        return parts.isEmpty ? "nothing listed" : parts.joined(separator: "; ")
    }

    /// What a listing that arrives does.
    enum Arrival: Equatable {
        /// The picker is open for this listing: show these mailboxes.
        case show([Mailbox])
        /// The picker closed or opened again since: nothing changes on screen.
        case dropped
        /// Nothing to show at all: close the picker and say why.
        case fail
    }

    /// A listing has arrived for `opening`; `boxes` empty when it failed. The cache is
    /// updated either way when the listing has mailboxes.
    static func arrival(boxes: [Mailbox], for opening: Int, current: Int, pickerOpen: Bool, cached: [Mailbox]?) -> Arrival {
        guard opening == current, pickerOpen else { return .dropped }
        if !boxes.isEmpty { return .show(boxes) }
        if let cached, !cached.isEmpty { return .show(cached) }
        return .fail
    }

    /// Opens the picker over Mail's mailboxes at once (from this session's list, or a short
    /// "Listing mailboxes…") and fills it when Mail answers, off the main thread. The choice
    /// moves Mail's selected messages; the move checks the selection when it runs.
    static func showPicker(scripting: MailFilingScripting = AppleScriptMailFiling()) {
        opening += 1
        let mine = opening
        let started = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
        let choose: (Mailbox) -> Void = { chosen in
            MailMenu.running?.activate()
            Task { @MainActor in
                let report = await scripting.move(to: chosen)
                if report.outcome == .moved { saveRecent(remember(chosen, in: loadRecent())) }
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: report.title, subtitle: report.subtitle),
                                            for: report.outcome == .moved ? MailHelpers.successToast : .seconds(6))
            }
        }
        Task { @MainActor in
            // The selected messages' account, from the messages themselves.
            let account: String
            switch scope(of: await scripting.selectionAccounts()) {
            case .nothingSelected:
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: "Can't file", subtitle: "Select a message in Mail first"), for: .seconds(4))
                return
            case .mixed:
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: "Select messages from one account",
                                                  subtitle: "A move across accounts makes a copy"), for: .seconds(5))
                return
            case .account(let one):
                account = one
            }
            var stored = loadCache()
            let cached = pickerList(account: account, own: stored[account] ?? [], local: stored[""] ?? [])
            let recent = { (list: [Mailbox]) in loadRecent().filter { list.contains($0) } }
            let shownAtOnce = !cached.isEmpty
            if shownAtOnce {
                MailboxPicker.shared.show(mailboxes: cached, recent: recent(cached), onChoose: choose)
                SnoozeLog.append(["picker: shown from the saved list in \(ms()) ms, \(cached.count) mailboxes"], to: MailScript.logURL)
            }
            // Refreshed behind it: this account's mailboxes, then On My Mac's.
            let own = await scripting.mailboxes(of: account)
            let local = account.isEmpty ? own : await scripting.mailboxes(of: "")
            if !own.isEmpty { stored[account] = own }
            if !account.isEmpty, !local.isEmpty { stored[""] = local }
            saveCache(stored)
            let fresh = pickerList(account: account, own: own, local: local)
            SnoozeLog.append(["picker: Mail's list arrived after \(ms()) ms, \(fresh.count) mailboxes"], to: MailScript.logURL)
            let pickerOpen = shownAtOnce ? MailboxPicker.shared.isOpen : true
            switch arrival(boxes: fresh, for: mine, current: opening, pickerOpen: pickerOpen, cached: cached.isEmpty ? nil : cached) {
            case .show(let list):
                if shownAtOnce { MailboxPicker.shared.update(mailboxes: list) } else {
                    MailboxPicker.shared.show(mailboxes: list, recent: recent(list), onChoose: choose)
                    SnoozeLog.append(["picker: shown after \(ms()) ms (nothing saved yet)"], to: MailScript.logURL)
                }
            case .dropped:
                break
            case .fail:
                if shownAtOnce { MailboxPicker.shared.close() }
                let problem = scripting.lastProblem ?? (title: "Can't file", subtitle: "Mail returned no mailboxes")
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: problem.title, subtitle: problem.subtitle), for: .seconds(8))
            }
        }
    }
}

/// What filing asks Mail. A protocol, so tests use a fake and never move mail.
@MainActor
protocol MailFilingScripting {
    func mailboxes() async -> [MailFiling.Mailbox]
    /// The account of each selected message (empty for On My Mac).
    func selectionAccounts() async -> [String]
    /// One account's mailboxes (On My Mac's for an empty name).
    func mailboxes(of account: String) async -> [MailFiling.Mailbox]
    /// Why the last listing came back empty, when Mail's script said so.
    var lastProblem: (title: String, subtitle: String)? { get }
    /// Moves the viewer's selected messages; nil when done, or why not.
    func move(to mailbox: MailFiling.Mailbox) async -> MailFiling.MoveReport
}

struct AppleScriptMailFiling: MailFilingScripting {
    /// Why the last listing came back empty, when a script error says so.
    var lastProblem: (title: String, subtitle: String)? { AppleScriptMailFiling.problemBox.value }
    final class Box { var value: (title: String, subtitle: String)? }
    static let problemBox = Box()

    func mailboxes() async -> [MailFiling.Mailbox] {
        let source = Self.listingSource
        return await list(source)
    }

    func selectionAccounts() async -> [String] {
        let text = await MailScript.run("selection accounts", MailScripts.selectionAccounts).text ?? ""
        return MailFiling.accountLines(text)
    }

    func mailboxes(of account: String) async -> [MailFiling.Mailbox] {
        let started = Date()
        let text = await MailScript.run("list one account", MailScripts.accountListing(account)).text ?? ""
        let place = account.isEmpty ? "On My Mac" : "the account"
        if let paths = MailFiling.bulkPaths(text.split(separator: "\n").map(String.init)) {
            SnoozeLog.append(["list one account: \(place), \(paths.count) mailboxes in \(Int(Date().timeIntervalSince(started) * 1000)) ms"], to: MailScript.logURL)
            return paths.map { MailFiling.Mailbox(account: account, path: $0) }
        }
        // Mail's bulk answer didn't line up: the full walk, kept to this account.
        SnoozeLog.append(["list one account: \(place), bulk answer didn't line up; full walk"], to: MailScript.logURL)
        return await mailboxes().filter { $0.account == account }
    }

    /// The listing script; its handler talks to Mail inside its own tell block.
    nonisolated static let listingSource = """
        -- Every variable starts with "os": inside a tell to Mail a plain word such as scope,
        -- name, id or result is Mail's own term (2026-11-20: "set scope" failed with -10006,
        -- and the earlier -1700 came from a parameter named scope). Mail is asked only in
        -- one-line tells; the text is built outside them. A test compiles this script and
        -- checks no variable is an application term.
        -- A "\\" or "/" inside a folder's own name gets a backslash before it, so the path
        -- splits back into the same names.
        on osEscape(osText)
            set osSaved to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "\\\\"
            set osParts to text items of osText
            set AppleScript's text item delimiters to "\\\\\\\\"
            set osText to osParts as text
            set AppleScript's text item delimiters to "/"
            set osParts to text items of osText
            set AppleScript's text item delimiters to "\\\\/"
            set osText to osParts as text
            set AppleScript's text item delimiters to osSaved
            return osText
        end osEscape

        on osWalk(osBoxes, osPrefix, osAccountTitle, osScopeName)
            set osOut to ""
            repeat with osIndex from 1 to (count of osBoxes)
                set osStage to "item"
                try
                    set osBox to item osIndex of osBoxes
                    set osStage to "name"
                    tell application id "com.apple.mail" to set osBoxName to name of osBox
                    if osBoxName is not missing value then
                        set osStage to "text"
                        set osPath to osPrefix & my osEscape(osBoxName as text)
                        set osOut to osOut & osAccountTitle & tab & osPath & linefeed
                        set osStage to "children"
                        tell application id "com.apple.mail" to set osChildren to mailboxes of osBox
                        set osOut to osOut & my osWalk(osChildren, osPath & "/", osAccountTitle, osScopeName)
                    end if
                on error osMessage number osNumber
                    set osOut to osOut & "#SKIP" & tab & osScopeName & " " & (osNumber as text) & " at " & osStage & ": " & osMessage & linefeed
                end try
            end repeat
            return osOut
        end osWalk

        with timeout of 20 seconds
            set osOut to ""
            try
                tell application id "com.apple.mail" to set osTop to mailboxes
                set osOut to osOut & "#STEP" & tab & "On My Mac got " & ((count of osTop) as text) & linefeed
                set osOut to osOut & my osWalk(osTop, "", "", "On My Mac") & "#DONE" & tab & "On My Mac" & linefeed
            on error osMessage number osNumber
                set osOut to osOut & "#ERR" & tab & "On My Mac " & (osNumber as text) & ": " & osMessage & linefeed
            end try
            try
                tell application id "com.apple.mail" to set osAccounts to every account
            on error osMessage number osNumber
                return osOut & "#ERR" & tab & "accounts " & (osNumber as text) & ": " & osMessage & linefeed
            end try
            set osAccountIndex to 0
            repeat with osAccountRef in osAccounts
                set osAccountIndex to osAccountIndex + 1
                set osScopeName to "account " & (osAccountIndex as text)
                try
                    tell application id "com.apple.mail" to set osEnabled to enabled of osAccountRef
                    if osEnabled then
                        tell application id "com.apple.mail" to set osAccountBoxes to mailboxes of osAccountRef
                        tell application id "com.apple.mail" to set osAccountTitle to name of osAccountRef
                        set osOut to osOut & "#STEP" & tab & osScopeName & " got " & ((count of osAccountBoxes) as text) & linefeed
                        set osOut to osOut & my osWalk(osAccountBoxes, "", (osAccountTitle as text), osScopeName) & "#DONE" & tab & osScopeName & linefeed
                    else
                        set osOut to osOut & "#OFF" & tab & osScopeName & linefeed
                    end if
                on error osMessage number osNumber
                    set osOut to osOut & "#ERR" & tab & osScopeName & " " & (osNumber as text) & ": " & osMessage & linefeed
                end try
            end repeat
            return osOut
        end timeout
        """

    private func list(_ source: String) async -> [MailFiling.Mailbox] {
        let outcome = await MailScript.run("list mailboxes", source)
        Self.problemBox.value = MailScript.problem(outcome)
        guard let text = outcome.text else { return [] }
        let lines = text.split(separator: "\n")
        let failures = lines.filter { $0.hasPrefix("#ERR\t") }.map { $0.dropFirst(5) }
        if !failures.isEmpty { SnoozeLog.append(["list mailboxes: not read: \(failures.joined(separator: ", "))"], to: MailScript.logURL) }
        // The step markers go to the log only when something failed; a good run is one
        // summary line (David's listing worked on 2026-11-20).
        let failed = lines.contains { $0.hasPrefix("#FAIL\t") || $0.hasPrefix("#SKIP\t") || $0.hasPrefix("#ERR\t") }
        let diagnostics = lines.filter { failed && ($0.hasPrefix("#STEP\t") || $0.hasPrefix("#FAIL\t") || $0.hasPrefix("#SKIP\t") || $0.hasPrefix("#ERR\t")) }
            .prefix(60).map { "list mailboxes: " + MailScript.scrubbed(String($0.dropFirst(1)).replacingOccurrences(of: "\t", with: " ")) }
        if !diagnostics.isEmpty { SnoozeLog.append(Array(diagnostics), to: MailScript.logURL) }
        let summary = MailFiling.listingSummary(lines.map(String.init))
        SnoozeLog.append(["list mailboxes: \(summary)"], to: MailScript.logURL)
        let boxes: [MailFiling.Mailbox] = lines.filter { !$0.hasPrefix("#") }.compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[1].isEmpty else { return nil }
            return MailFiling.Mailbox(account: String(parts[0]), path: String(parts[1]))
        }
        SnoozeLog.append(["list mailboxes: \(boxes.count) mailboxes"], to: MailScript.logURL)
        if boxes.isEmpty, Self.problemBox.value == nil {
            let first = failures.first.map { " (\($0))" } ?? ""
            Self.problemBox.value = (title: "Can't file", subtitle: "Mail returned no mailboxes\(first)")
        }
        return boxes
    }

    /// Moves the viewer's selection to `mailbox` with one script that resolves the folder name
    /// by name and proves it exists before moving anything, then reads back where each
    /// message is (2026-11-20: a move "succeeded" and nothing moved). Mail's Move to menu
    /// can't be used: its folder lists are built only when the menu opens (keys.log: "3 of
    /// 4 parts found, 0 items at the last one"). Nothing is ever deleted to tidy up.
    func move(to mailbox: MailFiling.Mailbox) async -> MailFiling.MoveReport {
        let chain = mailbox.chain
        guard !chain.isEmpty else { return MailFiling.report(.notMoved, total: 0, to: mailbox, problem: "No folder chosen") }
        let outcome = await MailScript.run("move and check", MailScripts.moveAndCheck(account: mailbox.account, chain: chain))
        if let problem = MailScript.problem(outcome) {
            return MailFiling.report(.notMoved, total: 0, to: mailbox, problem: "\(problem.title): \(problem.subtitle)")
        }
        let result = MailFiling.moveResult(outcome.text ?? "")
        SnoozeLog.append(["move: \(mailbox.account.isEmpty ? "to On My Mac" : "to an account mailbox"), \(chain.count) level\(chain.count == 1 ? "" : "s") deep: \(result.logLine)"], to: MailScript.logURL)
        return result.report(to: mailbox)
    }
}
