import AppKit

/// Message links (MAIL-PLAN slice D): copies a link that opens the selected message in
/// Mail, built from its Message-ID.
@MainActor
enum MailLinks {
    /// `message://%3C…%3E`, the form Mail opens. Everything but letters, digits and
    /// `-._~@` is escaped, so `+`, `/`, `%` and spaces in an id survive.
    static func link(forMessageID id: String) -> URL? {
        let bare = id.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\n"))
        guard !bare.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@")
        guard let escaped = bare.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://%3C\(escaped)%3E")
    }

    /// Copies the link of the one message selected in Mail's viewer.
    static func copyLink(
        scripting: MailScripting = AppleScriptMail(),
        pasteboard: NSPasteboard = .general,
        tell: (Toast, Duration) -> Void = { ToastController.shared.show($0, for: $1) }
    ) {
        let selected = scripting.selectedMessages()
        guard selected.count == 1, let message = selected.first, let url = link(forMessageID: message.id) else {
            tell(Toast(systemImage: "link", title: "No link copied", subtitle: selected.isEmpty ? "Select a message in Mail first" : "Select one message"), .seconds(3))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        tell(Toast(systemImage: "link", title: "Link copied", subtitle: message.subject), MailHelpers.successToast)
    }
}
