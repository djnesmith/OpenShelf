import Foundation

/// Runs one of the Mail helpers' AppleScripts and records how it went in
/// ~/Library/Logs/OpenShelf/mail-scripts.log: the script's name, a count of lines back or
/// the error number with its message, quoted names taken out (2026-11-20: filing said
/// "Mail listed no mailboxes" and nothing said why).
@MainActor
enum MailScript {
    struct Outcome {
        var text: String?
        /// The OSA error number, nil when the script ran.
        var error: Int?
        var message: String?
    }

    /// "Not authorized to send Apple events" (errAEEventNotPermitted).
    static let notPermitted = -1743

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenShelf/mail-scripts.log")
    }

    /// One serial queue for every Mail script, off the main thread: a slow Mail must not
    /// freeze the wheel, the hotkeys or the key tap (2026-11-20).
    nonisolated static let queue = DispatchQueue(label: "com.djnesmith.OpenShelf.mail-scripts")

    /// Runs `source` on the scripts' queue and logs the outcome back on the main thread.
    static func run(_ name: String, _ source: String) async -> Outcome {
        let (text, number, message) = await withCheckedContinuation { (done: CheckedContinuation<(String?, Int?, String?), Never>) in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                done.resume(returning: (result?.stringValue, error?[NSAppleScript.errorNumber] as? Int, error?[NSAppleScript.errorMessage] as? String))
            }
        }
        if let number {
            SnoozeLog.append(["\(name): error \(number) \(scrubbed(message ?? ""))"], to: logURL)
        } else {
            let lines = (text ?? "").split(separator: "\n").count
            SnoozeLog.append(["\(name): ok, \(lines) line\(lines == 1 ? "" : "s")"], to: logURL)
        }
        return Outcome(text: text, error: number, message: message)
    }

    /// An error message without the names it quotes (mailboxes, accounts, addresses).
    static func scrubbed(_ message: String) -> String {
        message.replacingOccurrences(of: #"[“"][^”"]*[”"]"#, with: "“…”", options: .regularExpression)
    }

    /// What to tell David when a Mail script failed: the permission and where to give it,
    /// or the error number.
    static func problem(_ outcome: Outcome) -> (title: String, subtitle: String)? {
        guard let error = outcome.error else { return nil }
        if error == notPermitted {
            return ("Allow OpenShelf to control Mail", "System Settings › Privacy & Security › Automation › OpenShelf › Mail")
        }
        return ("Mail's script failed", "Error \(error)\(error == -1712 ? ", Mail was slow to answer" : ""); see mail-scripts.log")
    }
}
