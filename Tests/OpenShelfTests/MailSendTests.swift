import Foundation
import Testing
@testable import OpenShelf

/// Send and Archive archives only the message the reply answers, when that is certain.
@MainActor
struct MailSendTests {
    @Test(arguments: [
        ("Re: Lunch", "lunch"),
        ("RE: re: Fwd:  Lunch ", "lunch"),
        ("AW: Treffen", "treffen"),
        ("Lunch", "lunch"),
        ("Re:", ""),
        ("Return policy", "return policy"),
    ])
    func baseSubjects(subject: String, expected: String) {
        #expect(MailSend.baseSubject(subject) == expected)
    }

    @Test func archivesOnlyTheOneMatchingSelectedMessage() {
        let lunch = MailSend.Selected(id: "<a@x>", subject: "Lunch")
        let other = MailSend.Selected(id: "<b@x>", subject: "Budget")
        #expect(MailSend.original(forReply: "Re: Lunch", selected: [lunch]) == lunch)
        #expect(MailSend.original(forReply: "Fwd: Lunch", selected: [lunch]) == lunch)
        // A different subject, several or no messages selected, a new message, no id: not archived.
        #expect(MailSend.original(forReply: "Re: Lunch", selected: [other]) == nil)
        #expect(MailSend.original(forReply: "Re: Lunch", selected: [lunch, other]) == nil)
        #expect(MailSend.original(forReply: "Re: Lunch", selected: []) == nil)
        #expect(MailSend.original(forReply: "New Message", selected: [lunch]) == nil)
        #expect(MailSend.original(forReply: "Re:", selected: [MailSend.Selected(id: "<c@x>", subject: "")]) == nil)
        #expect(MailSend.original(forReply: "Re: Lunch", selected: [MailSend.Selected(id: "", subject: "Lunch")]) == nil)
    }

    @Test func theSendKeysAreCommandReturnAndShiftCommandReturn() {
        #expect(MailSend.sendShortcut.displayString == "⌘↩")
        #expect(MailSend.sendAndArchiveShortcut.displayString == "⇧⌘↩")
        #expect(MailHelpers(defaults: UserDefaults(suiteName: "OpenShelfTests.mail.\(UUID())")!).sendKeys)
    }
}
