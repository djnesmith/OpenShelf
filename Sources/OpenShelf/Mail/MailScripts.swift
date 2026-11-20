import Foundation

/// The Mail helpers' AppleScripts in one place, so a test can compile each and check that
/// no variable is one of Mail's own terms (2026-11-20). They are only ever run through
/// MailScript.run. Names that a tell to Mail could read as its terms are avoided.
enum MailScripts {
    /// The viewer's selected messages: Message-ID and subject, one per line.
    static let selectedMessages = """
    tell application id "com.apple.mail"
        set out to ""
        repeat with m in (selection as list)
            set out to out & (message id of m) & tab & (subject of m) & linefeed
        end repeat
        return out
    end tell
    """

    /// The selected messages' sender addresses, one per line.
    static let selectedSenders = """
    tell application id "com.apple.mail"
        set out to ""
        repeat with m in (selection as list)
            set out to out & (extract address from (sender of m)) & linefeed
        end repeat
        return out
    end tell
    """

    /// The selected messages' ids with their flag and read states.
    static let selectionState = """
    tell application id "com.apple.mail"
        set out to ""
        repeat with m in (selection as list)
            set out to out & (message id of m) & tab & (flagged status of m as text) & tab & (read status of m as text) & linefeed
        end repeat
        return out
    end tell
    """

    /// AppleScript text in quotes.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Mail's specifier for a mailbox: "INBOX" of an account, or a path in On My Mac.
    static func specifier(account: String, path: String) -> String {
        account.isEmpty ? "mailbox \(quoted(path))" : "mailbox \(quoted(path)) of account \(quoted(account))"
    }

    /// Where each selected message is: its Message-ID, its account (empty for On My Mac)
    /// and its mailbox's path, one per line (2026-11-20: a move back to the Inbox left a
    /// copy, and moves are now checked against their source).
    static let selectionPlaces = """
    tell application id "com.apple.mail" to set osPicked to selection as list
    set osOut to ""
    repeat with osIndex from 1 to (count of osPicked)
        set osMessage to item osIndex of osPicked
        tell application id "com.apple.mail"
            set osId to message id of osMessage
            set osBox to mailbox of osMessage
            set osPath to name of osBox
            set osAccountTitle to ""
            try
                set osAccountTitle to name of account of osBox
            end try
        end tell
        repeat
            try
                tell application id "com.apple.mail" to set osBox to container of osBox
                -- A top-level mailbox's container may be its account: stop there.
                tell application id "com.apple.mail" to set osIsBox to (class of osBox is mailbox)
                if not osIsBox then exit repeat
                tell application id "com.apple.mail" to set osParent to name of osBox
                set osPath to osParent & "/" & osPath
            on error
                exit repeat
            end try
        end repeat
        set osOut to osOut & osId & tab & osAccountTitle & tab & osPath & linefeed
    end repeat
    return osOut
    """

    /// How many of `places` (id, source specifier) are still in their source, and how many
    /// are in `destination`, by Message-ID.
    static func placeCounts(_ places: [(id: String, source: String)], destination: String) -> String {
        let rows = places.map { "{\(quoted($0.id)), \($0.source)}" }.joined(separator: ", ")
        return """
        with timeout of 20 seconds
            tell application id "com.apple.mail"
                set osPlaces to {\(rows)}
                set osDestination to \(destination)
            end tell
            set osInSource to 0
            set osInDestination to 0
            repeat with osIndex from 1 to (count of osPlaces)
                set osPlace to item osIndex of osPlaces
                set osId to item 1 of osPlace
                set osSource to item 2 of osPlace
                tell application id "com.apple.mail"
                    set osInSource to osInSource + (count of (messages of osSource whose message id is osId))
                    set osInDestination to osInDestination + (count of (messages of osDestination whose message id is osId))
                end tell
            end repeat
            return (osInSource as text) & tab & (osInDestination as text)
        end timeout
        """
    }

    /// Moves the viewer's selected messages to `target` (a mailbox specifier).
    static func move(to target: String) -> String {
        """
        tell application id "com.apple.mail"
            set picked to selection as list
            if (count of picked) is 0 then return "Select a message in Mail first"
            move picked to \(target)
            return ""
        end tell
        """
    }
}
