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

        var display: String { account.isEmpty ? path : "\(path) — \(account)" }
    }

    static let recentKey = "MailFilingRecent"
    static let recentLimit = 10

    /// How well `query` matches `mailbox`, or nil for no match: every typed character in
    /// order (case ignored), scored higher for matches at the start of a word, in a row,
    /// and in the mailbox's own name rather than its parents'.
    static func score(_ query: String, _ mailbox: Mailbox) -> Int? {
        let typed = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !typed.isEmpty else { return 0 }
        let name = Array(mailbox.path.lowercased())
        let leafStart = (mailbox.path.lastIndex(of: "/").map { mailbox.path.distance(from: mailbox.path.startIndex, to: $0) + 1 }) ?? 0
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

    /// Opens the picker over Mail's mailboxes; the choice moves Mail's selected messages.
    static func showPicker(scripting: MailFilingScripting = AppleScriptMailFiling()) {
        let mailboxes = scripting.mailboxes()
        guard !mailboxes.isEmpty else {
            let problem = scripting.lastProblem ?? (title: "Can't file", subtitle: "Mail returned no mailboxes")
            ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: problem.title, subtitle: problem.subtitle), for: .seconds(8))
            return
        }
        MailboxPicker.shared.show(mailboxes: mailboxes, recent: loadRecent()) { chosen in
            MailMenu.running?.activate()
            if let problem = scripting.moveSelection(to: chosen) {
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: "Not moved", subtitle: problem), for: .seconds(4))
            } else {
                saveRecent(remember(chosen, in: loadRecent()))
                ToastController.shared.show(Toast(systemImage: "tray.and.arrow.down", title: "Moved", subtitle: chosen.display), for: MailHelpers.successToast)
            }
        }
    }
}

/// What filing asks Mail. A protocol, so tests use a fake and never move mail.
@MainActor
protocol MailFilingScripting {
    func mailboxes() -> [MailFiling.Mailbox]
    /// Why the last listing came back empty, when Mail's script said so.
    var lastProblem: (title: String, subtitle: String)? { get }
    /// Moves the viewer's selected messages; nil when done, or why not.
    func moveSelection(to mailbox: MailFiling.Mailbox) -> String?
}

struct AppleScriptMailFiling: MailFilingScripting {
    /// Why the last listing came back empty, when a script error says so.
    var lastProblem: (title: String, subtitle: String)? { AppleScriptMailFiling.problemBox.value }
    final class Box { var value: (title: String, subtitle: String)? }
    static let problemBox = Box()

    func mailboxes() -> [MailFiling.Mailbox] {
        let source = """
        on walk(boxes, prefix, accountName)
            set out to ""
            repeat with b in boxes
                set p to prefix & (name of b)
                set out to out & accountName & tab & p & linefeed
                set out to out & my walk(mailboxes of b, p & "/", accountName)
            end repeat
            return out
        end walk
        tell application id "com.apple.mail"
            with timeout of 20 seconds
                set out to ""
                try
                    set out to my walk(mailboxes, "", "")
                on error number n
                    set out to out & "#ERR" & tab & "On My Mac " & n & linefeed
                end try
                -- One account that can't be read (Exchange, a Gmail label, a slow server)
                -- doesn't hide the rest; its error number is reported, not its name.
                set i to 0
                repeat with a in accounts
                    set i to i + 1
                    try
                        if enabled of a then set out to out & my walk(mailboxes of a, "", name of a)
                    on error number n
                        set out to out & "#ERR" & tab & "account " & i & " " & n & linefeed
                    end try
                end repeat
                return out
            end timeout
        end tell
        """
        let outcome = MailScript.run("list mailboxes", source)
        Self.problemBox.value = MailScript.problem(outcome)
        guard let text = outcome.text else { return [] }
        let failures = text.split(separator: "\n").filter { $0.hasPrefix("#ERR\t") }.map { $0.dropFirst(5) }
        if !failures.isEmpty { SnoozeLog.append(["list mailboxes: not read: \(failures.joined(separator: ", "))"], to: MailScript.logURL) }
        let boxes: [MailFiling.Mailbox] = text.split(separator: "\n").filter { !$0.hasPrefix("#ERR\t") }.compactMap { line in
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

    func moveSelection(to mailbox: MailFiling.Mailbox) -> String? {
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let target = mailbox.account.isEmpty ? "mailbox \(quoted(mailbox.path))" : "mailbox \(quoted(mailbox.path)) of account \(quoted(mailbox.account))"
        let source = """
        tell application id "com.apple.mail"
            set picked to selection as list
            if (count of picked) is 0 then return "Select a message in Mail first"
            move picked to \(target)
            return ""
        end tell
        """
        let outcome = MailScript.run("move selection", source)
        if let problem = MailScript.problem(outcome) { return "\(problem.title): \(problem.subtitle)" }
        let text = outcome.text ?? ""
        return text.isEmpty ? nil : text
    }
}
