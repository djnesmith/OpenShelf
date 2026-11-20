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
        var hasSubmenu: Bool { lazy || !kids.isEmpty }
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
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.fast) { lines.append($0) }
        #expect(outcome == .pressed)
        #expect(menus.events.list == ["press Message", "press Move to", "press Gmail", "press [Info]"])
        #expect(lines.count == 5)
        // The log has level numbers and counts, never a title.
        #expect(!lines.joined().contains("Info"))
        #expect(!lines.joined().contains("Gmail"))
    }

    @Test func nestedFoldersAndTheInbox() async {
        let menus = Menus()
        let nested = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Clients/Acme")), bar: menus.bar, folders: [],
                                         anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(nested == .pressed)
        #expect(menus.acme.presses == 1)
        let again = Menus()
        let inbox = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "INBOX")), bar: again.bar, folders: [],
                                        anyOpen: again.anyOpen, limits: Self.fast) { _ in }
        #expect(inbox == .pressed)
        #expect(again.events.list.last == "press Inbox")
    }

    @Test func aMissingFolderCancelsEveryMenuAndPressesNothing() async {
        let menus = Menus()
        var lines: [String] = []
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Nope")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.short) { lines.append($0) }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 3 items", closed: true))
        #expect(menus.events.list == ["press Message", "press Move to", "press Gmail", "cancel Gmail", "cancel Move to", "cancel Message"])
        #expect(!menus.anyOpen())
        #expect(lines.last?.contains("menu closed: yes") == true)
    }

    @Test func aTitleTwiceAtOneLevelCancels() async {
        let menus = Menus(gmailFolders: ["[Info]"])
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: 2 matches among 4 items", closed: true))
        #expect(menus.info.presses == 0)
    }

    /// A greyed-out final folder (Mail greys the mailbox the messages are in) is never
    /// pressed, and says so instead of "not found".
    @Test func aDisabledFolderIsNotPressed() async {
        let menus = Menus()
        menus.info.isEnabled = false
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(outcome == .folderOff(closed: true))
        #expect(menus.info.presses == 0)
    }

    @Test func aLevelThatNeverFillsGivesUpInTime() async {
        let menus = Menus(fillAfter: .max)
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "[Info]")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 0 items", closed: true))
        // 200 ms at one read per 5 ms: about 40 reads, fewer on a busy run; no limit, hundreds.
        #expect(menus.gmail.reads <= 60)
        #expect(menus.info.presses == 0)
    }

    @Test func noMessageMenuOpensNothing() async {
        let menus = Menus()
        let outcome = await MoveMenu.walk([["Nachricht"], ["Move to"]], bar: menus.bar, folders: [], anyOpen: menus.anyOpen, limits: Self.fast) { _ in }
        #expect(outcome == .cancelled(reason: "no Message menu", closed: true))
        #expect(menus.events.list.isEmpty)
    }

    /// A menu still open after cancelling is cancelled once more after 300 ms; still open,
    /// the answer says so (the toast tells David to press Esc).
    @Test func aStuckMenuIsCancelledTwiceAndReported() async {
        let menus = Menus()
        menus.message.stuck = true
        let outcome = await MoveMenu.walk(MoveMenu.titles(for: .init(account: "Gmail", path: "Nope")), bar: menus.bar, folders: [],
                                          anyOpen: menus.anyOpen, limits: Self.short) { _ in }
        #expect(outcome == .cancelled(reason: "level 4 of 4: not found among 3 items", closed: false))
        #expect(menus.message.cancels == 2)
    }

    /// Mail's Move to as it is on David's Mail (2026-11-20, keys.log: 93 items, "level 3 is
    /// off"): one flat list, each account's name a greyed-out header, its folders after it;
    /// a parent folder holds a submenu (which may itself be greyed out); the folder the
    /// messages are in is greyed out.
    @MainActor struct FlatMenus {
        let events: Fake.Events
        let bar: [Fake]
        let message: Fake, moveTo: Fake, workInfo: Fake, gmailInbox: Fake, gmailInfo: Fake, clients: Fake, acme: Fake
        static let gmailFolders: Set<String> = ["INBOX", "Inbox", "[Info]", "Clients", "Sent Mail", "Projects"]

        static func item(_ title: String, enabled: Bool = true, _ events: Fake.Events) -> Fake {
            let fake = Fake(title, events: events)
            fake.isEnabled = enabled
            return fake
        }

        /// `indented`: nested folders as indented items after their parent instead of a
        /// submenu ("Projects" › "2025" and "2026", each with an "Notes", plus a top "Notes").
        init(indented: Bool = true) {
            let events = Fake.Events()
            self.events = events
            func item(_ title: String, enabled: Bool = true) -> Fake { Self.item(title, enabled: enabled, events) }
            workInfo = item("[Info]")
            gmailInbox = item("Inbox", enabled: false)
            gmailInfo = item("[Info]")
            acme = item("Acme")
            clients = Fake("Clients", [item("Clients"), acme], lazy: true, events: events)
            clients.isEnabled = false
            let projects = indented
                ? [item("Projects"), item("    2025"), item("        Notes"), item("    2026"), item("        Notes"), item("Notes")]
                : [item("Projects"), item("2025"), item("Notes"), item("2026"), item("Notes")]
            moveTo = Fake("Move to", [item("On My Mac", enabled: false), item("Old"), item(""),
                                      item("Work", enabled: false), item("Inbox"), workInfo, item(""),
                                      item("Gmail", enabled: false), gmailInbox, gmailInfo, clients, item("Sent Mail")] + projects,
                          lazy: true, events: events)
            message = Fake("Message", [item("Archive"), moveTo], lazy: true, events: events)
            bar = [item("Mail"), message]
        }

        func anyOpen() -> Bool { bar.contains { $0.isOpen } }

        func walk(_ account: String, _ path: String, folders: Set<String> = gmailFolders, log: (String) -> Void = { _ in }) async -> MoveMenu.Outcome {
            await MoveMenu.walk(MoveMenu.titles(for: .init(account: account, path: path)), bar: bar, folders: folders,
                                anyOpen: anyOpen, limits: MailMoveMenuTests.fast, log: log)
        }

        func pressed(_ title: String) -> Int { events.list.filter { $0 == "press \(title)" }.count }
    }

    @Test func aFlatListFindsTheFolderInItsAccountsSection() async {
        let menus = FlatMenus()
        #expect(await menus.walk("Gmail", "[Info]") == .pressed)
        #expect(menus.gmailInfo.presses == 1)
        #expect(menus.workInfo.presses == 0)
        #expect(menus.events.list == ["press Message", "press Move to", "press [Info]"])
    }

    @Test func aGreyedOutFolderOfTheAccountStaysInItsSection() async {
        let menus = FlatMenus()
        // Gmail's Inbox is greyed out (the messages are in it): the section goes on past it.
        #expect(await menus.walk("Gmail", "Sent Mail") == .pressed)
        let again = FlatMenus()
        #expect(await again.walk("Gmail", "INBOX") == .folderOff(closed: true))
        #expect(again.gmailInbox.presses == 0)
    }

    /// A greyed-out parent folder whose submenu opens is fine: only the final item must be
    /// enabled.
    @Test func aGreyedOutParentStillOpens() async {
        let menus = FlatMenus()
        #expect(await menus.walk("Gmail", "Clients/Acme") == .pressed)
        #expect(menus.acme.presses == 1)
        #expect(menus.events.list == ["press Message", "press Move to", "press Clients", "press Acme"])
    }

    /// A folder of another account is never picked: Work has no "Sent Mail", Gmail does.
    @Test func anotherAccountsFolderIsNeverPicked() async {
        let menus = FlatMenus()
        let outcome = await menus.walk("Work", "Sent Mail", folders: ["INBOX", "Inbox", "[Info]"])
        #expect(outcome == .cancelled(reason: "levels 4-4 not found in the section", closed: true))
        #expect(menus.events.list.filter { $0.hasPrefix("press") } == ["press Message", "press Move to"])
    }

    @Test func aFolderWithoutASubmenuCantBeAParent() async {
        let menus = FlatMenus()
        let outcome = await menus.walk("Gmail", "[Info]/Child")
        #expect(outcome == .cancelled(reason: "levels 4-5 not found in the section", closed: true))
        #expect(menus.gmailInfo.presses == 0)
    }

    @Test func theAccountsTopFoldersComeFromTheSavedList() {
        let cache = ["Gmail": [MailFiling.Mailbox(account: "Gmail", path: "INBOX"), .init(account: "Gmail", path: "Clients"),
                               .init(account: "Gmail", path: "Clients/Acme")]]
        #expect(MoveMenu.topFolders(of: "Gmail", cache: cache) == ["INBOX", "Inbox", "Clients"])
        #expect(MoveMenu.topFolders(of: "Work", cache: cache).isEmpty)
    }

    /// Nested folders as indented items: each level among the items under its parent; the
    /// top-level "Notes" and the two nested ones are told apart.
    @Test func indentedFoldersAreFoundUnderTheirParent() async {
        let menus = FlatMenus()
        #expect(await menus.walk("Gmail", "Projects/2026/Notes") == .pressed)
        let notes = menus.moveTo.kids.enumerated().filter { $0.element.title.hasSuffix("Notes") }.map { ($0.offset, $0.element.presses) }
        #expect(notes.map(\.1) == [0, 1, 0])
        let top = FlatMenus()
        #expect(await top.walk("Gmail", "Notes") == .pressed)
        #expect(top.moveTo.kids.last?.presses == 1)
    }

    /// Without indentation a leaf name used twice can't be told apart: nothing is pressed
    /// and the toast says so; a unique leaf is still found.
    @Test func withoutIndentationATwiceUsedNameCancels() async {
        let menus = FlatMenus(indented: false)
        #expect(await menus.walk("Gmail", "Projects/2026/Notes") == .ambiguous(closed: true))
        #expect(menus.pressed("Notes") == 0)
        let unique = FlatMenus(indented: false)
        #expect(await unique.walk("Gmail", "Projects/2026") == .pressed)
        #expect(unique.pressed("2026") == 1)
    }

    @Test func theShapeOfMoveToIsLoggedWithoutNames() async {
        var lines: [String] = []
        _ = await FlatMenus().walk("Gmail", "[Info]") { lines.append($0) }
        let shape = lines.first { $0.contains("Move to holds") }
        #expect(shape == "menu: Move to holds 18 items, 5 off, 1 with submenus, 2 separators, 4 indented (up to 8 spaces)")
        #expect(!lines.joined().contains("Info"))
        #expect(!lines.joined().contains("Gmail"))
    }

    @Test func flatFindAlone() {
        let events = Fake.Events()
        let section: [MoveMenu.Node] = ["A", "  B", "    C", "  C", "D"].map { FlatMenus.item($0, events) }
        #expect(MoveMenu.flatFind([["A"], ["B"], ["C"]], in: section) == .found(2))
        #expect(MoveMenu.flatFind([["A"], ["C"]], in: section) == .found(3))
        #expect(MoveMenu.flatFind([["D"]], in: section) == .found(4))
        #expect(MoveMenu.flatFind([["A"], ["X"]], in: section) == .notFound)
        let flat: [MoveMenu.Node] = ["A", "C", "B", "C"].map { FlatMenus.item($0, events) }
        #expect(MoveMenu.flatFind([["A"], ["C"]], in: flat) == .twoOrMore)
        #expect(MoveMenu.flatFind([["A"], ["B"]], in: flat) == .found(2))
    }
}
