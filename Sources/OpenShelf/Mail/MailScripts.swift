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
