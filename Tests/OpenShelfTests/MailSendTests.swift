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

    /// ⌘↩ typed into a panel over Mail never sends; nor does it with Send disabled.
    @Test func sendsOnlyWhenMailHasTheKeyboard() {
        #expect(MailSend.mayPress(sendEnabled: true, mailHasFocus: true))
        #expect(!MailSend.mayPress(sendEnabled: true, mailHasFocus: false))
        #expect(!MailSend.mayPress(sendEnabled: false, mailHasFocus: true))
    }

    @Test func theSendKeysAreCommandReturnAndShiftCommandReturn() {
        #expect(MailSend.sendShortcut.displayString == "⌘↩")
        #expect(MailSend.sendAndArchiveShortcut.displayString == "⇧⌘↩")
        #expect(MailHelpers(defaults: UserDefaults(suiteName: "OpenShelfTests.mail.\(UUID())")!).sendKeys)
    }

    /// ⌘↩ presses Send only when it is there, on, and Mail has the keyboard; otherwise it
    /// says why (David's Check Mail, 2026-11-20: Send is "not found" in the viewer).
    @Test func sendSaysWhyWhenItDoesNothing() {
        #expect(MailSend.outcome(sendFound: true, sendEnabled: true, mailHasFocus: true) == .press)
        #expect(MailSend.outcome(sendFound: false, sendEnabled: false, mailHasFocus: true) == .notWriting)
        #expect(MailSend.outcome(sendFound: true, sendEnabled: false, mailHasFocus: true) == .sendOff)
        #expect(MailSend.outcome(sendFound: true, sendEnabled: true, mailHasFocus: false) == .notMail)
        #expect(MailSend.Outcome.press.reason == nil)
        for outcome in [MailSend.Outcome.notWriting, .sendOff, .notMail] { #expect(outcome.reason?.isEmpty == false) }
    }

    /// Check Mail writes shortcuts as people do: Accessibility's 0 is ⌘ alone.
    @Test func checkMailReadsShortcuts() {
        #expect(MailCheck.readable(char: "E", modifiers: 0) == "⌘E")
        #expect(MailCheck.readable(char: "↩", modifiers: 0) == "⌘↩")
        #expect(MailCheck.readable(char: "D", modifiers: 1) == "⇧⌘D")
        #expect(MailCheck.readable(char: "A", modifiers: 4) == "⌃⌘A")
        #expect(MailCheck.readable(char: "x", modifiers: 8) == "x")
        #expect(MailCheck.readable(char: nil, modifiers: 8) == "no shortcut")
    }
}
