import Foundation
import Testing
@testable import OpenShelf

/// Mail's Move to menu, walked level by level with fake menus: a folder level shows its
/// items only after it opens (Mail builds it then), and any doubt cancels every opened
/// menu and presses nothing.
@MainActor
struct MailMoveMenuTests {
    final class Fake: MoveMenu.Node {
        let title: String
        var isEnabled = true
        var kids: [Fake]
        /// Items show only once pressed open, after this long.
        var lazy: Bool
        /// How many reads of an open menu pass before its items show (Mail filling it in);
        /// counted, not timed, so a busy test run can't change the answer.
        var fillAfter = 0
        var reads = 0
        var pressedAt: ContinuousClock.Instant?
        var presses = 0
        var cancels = 0
        /// A menu that won't close when cancelled.
        var stuck = false
        let events: Events

        final class Events { var list: [String] = [] }

        init(_ title: String, _ kids: [Fake] = [], lazy: Bool = false, events: Events) {
            self.title = title; self.kids = kids; self.lazy = lazy; self.events = events
        }

        var items: [MoveMenu.Node] {
            guard lazy else { return kids }
            guard pressedAt != nil else { return [] }
            reads += 1
            return reads > fillAfter ? kids : []
        }

        func press() -> Bool {
            presses += 1
            pressedAt = .now
            events.list.append("press \(title)")
            return true
        }

        func cancel() {
            cancels += 1
            events.list.append("cancel \(title)")
            if !stuck { pressedAt = nil }
        }

        var isOpen: Bool { pressedAt != nil && !kids.isEmpty }
    }

    /// Message › Move to › Gmail › INBOX, [Info], Clients › Acme; the account's folders are
    /// built only when it opens.
    @MainActor struct Menus {
        let events: Fake.Events
        let bar: [Fake]
        let message: Fake, moveTo: Fake, gmail: Fake, info: Fake, clients: Fake, acme: Fake

        init(gmailFolders extra: [String] = [], fillAfter: Int = 0) {
            let events = Fake.Events()
            self.events = events
            acme = Fake("Acme", events: events)
            clients = Fake("Clients", [acme], lazy: true, events: events)
            info = Fake("[Info]", events: events)
            gmail = Fake("Gmail", [Fake("Inbox", events: events), info, clients] + extra.map { Fake($0, events: events) }, lazy: true, events: events)
            gmail.fillAfter = fillAfter
            moveTo = Fake("Move to", [Fake("Work", events: events), gmail], lazy: true, events: events)
            message = Fake("Message", [Fake("Archive", events: events), moveTo], lazy: true, events: events)
            bar = [Fake("Mail", events: events), Fake("File", events: events), message]
        }

        func anyOpen() -> Bool { bar.contains { $0.isOpen } }
    }

    /// Generous where the folder is found (a busy parallel run can starve the main actor for
    /// seconds); `short` where the walk must give up.
    nonisolated static let fast = MoveMenu.Limits(level: .seconds(30), total: .seconds(60), poll: .milliseconds(5))
    nonisolated static let short = MoveMenu.Limits(level: .milliseconds(200), total: .seconds(1), poll: .milliseconds(5))

    @Test func titlesPerLevel() {
        #expect(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")) == [["Message"], ["Move to"], ["Gmail"], ["[Info]"]])
        #expect(MoveMenu.titles(for: .init(account: "Gmail", path: "INBOX")) == [["Message"], ["Move to"], ["Gmail"], ["INBOX", "Inbox"]])
        #expect(MoveMenu.titles(for: .init(account: "", path: "Old/2026")) == [["Message"], ["Move to"], ["On My Mac"], ["Old"], ["2026"]])
        #expect(MoveMenu.titles(for: .init(account: "Gmail", path: MailFiling.joinPath(["a/b", "INBOX"]))) == [["Message"], ["Move to"], ["Gmail"], ["a/b"], ["INBOX"]])
    }

    @Test func opensEachLevelAndPressesTheFolder() async {
        let menus = Menus(fillAfter: 3)
        var lines: [String] = []
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.fast) { lines.append($0) }
        #expect(outcome == .pressed)
        #expect(menus.events.list == ["press Message", "press Move to", "press Gmail", "press [Info]"])
        #expect(lines.count == 4)
        // The log has level numbers and counts, never a title.
        #expect(!lines.joined().contains("Info"))
        #expect(!lines.joined().contains("Gmail"))
    }

    @Test func nestedFoldersAndTheInbox() async {
        let menus = Menus()
        let nested = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Clients/Acme")), bar: menus.bar,
                                         anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(nested == .pressed)
        #expect(menus.acme.presses == 1)
        let again = Menus()
        let inbox = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "INBOX")), bar: again.bar,
                                        anyOpen: again.anyOpen, limits: Self.fast) { _ in }
        #expect(inbox == .pressed)
        #expect(again.events.list.last == "press Inbox")
    }

    @Test func aMissingFolderCancelsEveryMenuAndPressesNothing() async {
        let menus = Menus()
        var lines: [String] = []
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Nope")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.short) { lines.append($0) }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 3 items", closed: true))
        #expect(menus.events.list == ["press Message", "press Move to", "press Gmail", "cancel Gmail", "cancel Move to", "cancel Message"])
        #expect(!menus.anyOpen())
        #expect(lines.last?.contains("menu closed: yes") == true)
    }

    @Test func aTitleTwiceAtOneLevelCancels() async {
        let menus = Menus(gmailFolders: ["[Info]"])
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: 2 matches among 4 items", closed: true))
        #expect(menus.info.presses == 0)
    }

    @Test func aDisabledFolderIsNotPressed() async {
        let menus = Menus()
        menus.info.isEnabled = false
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 is off", closed: true))
        #expect(menus.info.presses == 0)
    }

    @Test func aLevelThatNeverFillsGivesUpInTime() async {
        let menus = Menus(fillAfter: .max)
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 0 items", closed: true))
        // 200 ms at one read per 5 ms: about 40 reads, fewer on a busy run; no limit, hundreds.
        #expect(menus.gmail.reads <= 60)
        #expect(menus.info.presses == 0)
    }

    @Test func noMessageMenuOpensNothing() async {
        let menus = Menus()
        let outcome = await MoveMenu.walk([["Nachricht"], ["Move to"]], bar: menus.bar, anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(outcome == .cancelled(reason: "no Message menu", closed: true))
        #expect(menus.events.list.isEmpty)
    }

    /// A menu still open after cancelling is cancelled once more after 300 ms; still open,
    /// the answer says so (the toast tells David to press Esc).
    @Test func aStuckMenuIsCancelledTwiceAndReported() async {
        let menus = Menus()
        menus.message.stuck = true
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Nope")), bar: menus.bar,
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 3 items", closed: false))
        #expect(menus.message.cancels == 2)
    }
}
