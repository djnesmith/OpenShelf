import Foundation
import Testing
@testable import OpenShelf

/// Unsubscribe and block chooses from what Mail's own menu offers, and always asks first.
@MainActor
struct MailUnsubscribeTests {
    typealias Item = MailMenuTests.FakeItem

    @Test func plansFromMailsMenu() {
        #expect(MailUnsubscribe.plan(offered: [Item("Reply"), Item("Unsubscribe"), Item("Block Sender")]) == .unsubscribeAndBlock)
        #expect(MailUnsubscribe.plan(offered: [Item("Reply"), Item("Block Sender")]) == .blockOnly)
        #expect(MailUnsubscribe.plan(offered: [Item("Unsubscribe", enabled: false), Item("Block Sender")]) == .blockOnly)
        #expect(MailUnsubscribe.plan(offered: [Item("Unsubscribe")]) == .nothing)
        #expect(MailUnsubscribe.plan(offered: [Item("Reply"), Item("Block Sender", enabled: false)]) == .nothing)
        #expect(MailUnsubscribe.plan(offered: []) == .nothing)
    }

    @Test func asksWithTheSender() {
        #expect(MailUnsubscribe.question(for: .unsubscribeAndBlock, sender: "news@shop.example") == "Unsubscribe from news@shop.example and block it?")
        #expect(MailUnsubscribe.question(for: .blockOnly, sender: "a@b.example")?.hasPrefix("Mail offers no unsubscribe") == true)
        #expect(MailUnsubscribe.question(for: .nothing, sender: "a@b.example") == nil)
        #expect(MailUnsubscribe.shortcut.displayString == "⌃⌥U")
    }

    /// After the question, only the same one message may be unsubscribed and blocked.
    @Test func actsOnlyOnTheMessageConfirmed() {
        let a = MailSend.Selected(id: "<a@x>", subject: "News"), b = MailSend.Selected(id: "<b@x>", subject: "Other")
        #expect(MailUnsubscribe.stillSame(asked: [a], now: [a]))
        #expect(!MailUnsubscribe.stillSame(asked: [a], now: [b]))
        #expect(!MailUnsubscribe.stillSame(asked: [a], now: []))
        #expect(!MailUnsubscribe.stillSame(asked: [a, b], now: [a, b]))
        #expect(!MailUnsubscribe.stillSame(asked: [], now: []))
    }
}
