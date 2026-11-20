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


    /// The account of each selected message (empty for On My Mac), one per line, from the
    /// message itself, never from the mailbox showing (All Inboxes mixes accounts).
    static let selectionAccounts = """
    tell application id "com.apple.mail" to set osPicked to selection as list
    set osOut to ""
    repeat with osIndex from 1 to (count of osPicked)
        set osMessage to item osIndex of osPicked
        set osAccountTitle to ""
        try
            tell application id "com.apple.mail" to set osAccountTitle to name of account of mailbox of osMessage
        end try
        set osOut to osOut & osAccountTitle & linefeed
    end repeat
    return osOut
    """

    /// One account's mailboxes (or On My Mac's, for an empty name), three levels deep, in
    /// three bulk requests instead of one per mailbox (2026-11-20: v was slow). Lines:
    /// "#L1 name", "#L2 i name", "#L3 i j name" (i, j: the parent's place in its level).
    static func accountListing(_ account: String) -> String {
        let of = account.isEmpty ? "" : " of account \(quoted(account))"
        return """
        with timeout of 20 seconds
            tell application id "com.apple.mail"
                set osLevel1 to name of every mailbox\(of)
                set osLevel2 to name of every mailbox of every mailbox\(of)
                set osLevel3 to name of every mailbox of every mailbox of every mailbox\(of)
            end tell
            if (count of osLevel2) is not (count of osLevel1) then return "#MISALIGNED"
            set osOut to ""
            repeat with osI from 1 to (count of osLevel1)
                set osOut to osOut & "#L1" & tab & (item osI of osLevel1) & linefeed
            end repeat
            repeat with osI from 1 to (count of osLevel2)
                set osKids to item osI of osLevel2
                if (class of osKids) is not list then return "#MISALIGNED"
                repeat with osJ from 1 to (count of osKids)
                    set osOut to osOut & "#L2" & tab & (osI as text) & tab & (item osJ of osKids) & linefeed
                end repeat
            end repeat
            repeat with osI from 1 to (count of osLevel3)
                set osGroup to item osI of osLevel3
                if (class of osGroup) is not list then return "#MISALIGNED"
                repeat with osJ from 1 to (count of osGroup)
                    set osKids to item osJ of osGroup
                    if (class of osKids) is not list then return "#MISALIGNED"
                    repeat with osK from 1 to (count of osKids)
                        set osOut to osOut & "#L3" & tab & (osI as text) & tab & (osJ as text) & tab & (item osK of osKids) & linefeed
                    end repeat
                end repeat
            end repeat
            return osOut
        end timeout
        """
    }


    /// Moves the selected messages to the mailbox reached by `chain` in `account` (empty for On
    /// My Mac), and reads back from Mail where each one is (2026-11-20: a move "succeeded" and
    /// nothing moved; a mailbox addressed by a rebuilt path didn't resolve). The mailbox is
    /// resolved name by name and must exist before anything moves. Each message's id and
    /// source mailbox are taken first; after its move it is counted in the destination and
    /// in the source. Answers "#NOFOLDER n", "#NONE", or
    /// "#RESULT moved copied unchanged neither".
    static func moveAndCheck(account: String, chain: [String]) -> String {
        let names = "{" + chain.map(quoted).joined(separator: ", ") + "}"
        let first = account.isEmpty ? "mailbox (item 1 of osChain)" : "mailbox (item 1 of osChain) of account \(quoted(account))"
        return """
        with timeout of 60 seconds
            set osChain to \(names)
            -- Each level is checked to exist (asking its name) before the next, so a name
            -- that doesn't resolve says which level failed.
            set osLevel to 1
            try
                tell application id "com.apple.mail" to set osBox to \(first)
                tell application id "com.apple.mail" to set osBoxName to name of osBox
                repeat with osLevel from 2 to (count of osChain)
                    tell application id "com.apple.mail" to set osBox to mailbox (item osLevel of osChain) of osBox
                    tell application id "com.apple.mail" to set osBoxName to name of osBox
                end repeat
            on error osMessage number osNumber
                return "#NOFOLDER" & tab & (osNumber as text) & tab & (osLevel as text) & tab & ((count of osChain) as text)
            end try
            tell application id "com.apple.mail" to set osPicked to selection as list
            if (count of osPicked) is 0 then return "#NONE"
            set osIds to {}
            set osSources to {}
            repeat with osIndex from 1 to (count of osPicked)
                set osMessage to item osIndex of osPicked
                tell application id "com.apple.mail"
                    set end of osIds to message id of osMessage
                    set end of osSources to mailbox of osMessage
                end tell
            end repeat
            -- Setting the message's mailbox first: on a Gmail account the move command only
            -- adds the label and leaves the message where it was (2026-11-20). The move
            -- command runs only when setting the property raises an error. Either way the
            -- counts below, not the absence of an error, say what happened.
            set osFellBack to 0
            repeat with osIndex from 1 to (count of osPicked)
                set osMessage to item osIndex of osPicked
                try
                    tell application id "com.apple.mail" to set mailbox of osMessage to osBox
                on error
                    set osFellBack to osFellBack + 1
                    try
                        tell application id "com.apple.mail" to move osMessage to osBox
                    end try
                end try
            end repeat
            set osSourceName to ""
            try
                tell application id "com.apple.mail" to set osSourceName to name of (item 1 of osSources)
            end try
            delay 1
            set osMoved to 0
            set osCopied to 0
            set osUnchanged to 0
            set osNeither to 0
            repeat with osIndex from 1 to (count of osIds)
                set osId to item osIndex of osIds
                set osSource to item osIndex of osSources
                set osInBox to 0
                set osInSource to 0
                try
                    tell application id "com.apple.mail" to set osInBox to count of (messages of osBox whose message id is osId)
                end try
                try
                    tell application id "com.apple.mail" to set osInSource to count of (messages of osSource whose message id is osId)
                end try
                if osInBox > 0 and osInSource is 0 then
                    set osMoved to osMoved + 1
                else if osInBox > 0 then
                    set osCopied to osCopied + 1
                else if osInSource > 0 then
                    set osUnchanged to osUnchanged + 1
                else
                    set osNeither to osNeither + 1
                end if
            end repeat
            return "#RESULT" & tab & (osMoved as text) & tab & (osCopied as text) & tab & (osUnchanged as text) & tab & (osNeither as text) & tab & (osFellBack as text) & tab & osSourceName
        end timeout
        """
    }

}
