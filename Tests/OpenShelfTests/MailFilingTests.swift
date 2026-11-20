import AppKit
import Testing
@testable import OpenShelf

/// Quick filing's matching and the picker, and message links. Nothing here moves mail.
@MainActor
struct MailFilingTests {
    typealias Box = MailFiling.Mailbox
    static let boxes = [
        Box(account: "iCloud", path: "Bills"),
        Box(account: "iCloud", path: "Bills/Old"),
        Box(account: "iCloud", path: "Projects/OpenShelf"),
        Box(account: "Work", path: "Clients/Acme"),
        Box(account: "Work", path: "Receipts"),
        Box(account: "", path: "Archive 2019"),
    ]

    @Test func matchesTypedLettersInOrder() {
        #expect(MailFiling.rank("bill", in: Self.boxes, recent: []).first == Self.boxes[0])
        // Word starts beat letters scattered through a name: "os" is OpenShelf, not "ClientS".
        #expect(MailFiling.rank("os", in: Self.boxes, recent: []).first == Self.boxes[2])
        #expect(MailFiling.rank("acme", in: Self.boxes, recent: []) == [Self.boxes[3]])
        #expect(MailFiling.rank("zzz", in: Self.boxes, recent: []).isEmpty)
        #expect(MailFiling.score("RCPT", Self.boxes[4]) != nil)
        #expect(MailFiling.score("tpcr", Self.boxes[4]) == nil)
    }

    /// A letter at a word's start counts more ("b" is Bills, not Xbox); among equal matches
    /// the shorter name comes first ("bil" is Bilz before Bilaxx, against the alphabet).
    @Test func wordStartsAndShorterNamesWin() {
        let xbox = Box(account: "A", path: "Xbox"), bills = Box(account: "A", path: "Bills")
        #expect(MailFiling.rank("b", in: [xbox, bills], recent: []).first == bills)
        let short = Box(account: "A", path: "Bilz"), long = Box(account: "A", path: "Bilaxx")
        #expect(MailFiling.rank("bil", in: [long, short], recent: []).first == short)
    }

    @Test func recentMailboxesComeFirst() {
        let recent = [Self.boxes[4], Self.boxes[1]]
        #expect(Array(MailFiling.rank("", in: Self.boxes, recent: recent).prefix(2)) == recent)
        // Among equal matches the recent one wins: "Bills/Old" over "Bills" only by recency.
        #expect(MailFiling.rank("old", in: Self.boxes, recent: []).first == Self.boxes[1])
        var list: [Box] = []
        for box in Self.boxes + Self.boxes + [Self.boxes[2]] { list = MailFiling.remember(box, in: list) }
        #expect(list.first == Self.boxes[2])
        #expect(list.count == Self.boxes.count)
        #expect(Set(list).count == list.count)
        let many = (0..<20).map { Box(account: "A", path: "m\($0)") }
        #expect(many.reduce([]) { MailFiling.remember($1, in: $0) }.count == MailFiling.recentLimit)
    }

    @Test func recentMailboxesAreKept() {
        let defaults = UserDefaults(suiteName: "OpenShelfTests.filing.\(UUID())")!
        MailFiling.saveRecent([Self.boxes[3], Self.boxes[5]], defaults)
        #expect(MailFiling.loadRecent(defaults) == [Self.boxes[3], Self.boxes[5]])
    }

    /// The picker takes the keyboard without activating OpenShelf, with the cursor in
    /// the field, as the snooze prompt does (2026-11-20).
    @Test func thePickerOpensWithTheCursorInTheField() {
        let picker = MailboxPicker()
        let panel = picker.prepare(mailboxes: Self.boxes, recent: []) { _ in }
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(panel.initialFirstResponder === picker.pickerField)
    }

    /// ↓ moves the highlight, Return picks it; Esc picks nothing. Never put on screen here.
    @Test func thePickerChoosesWithArrowsAndReturn() {
        let picker = MailboxPicker()
        var chosen: [Box] = []
        picker.prepare(mailboxes: Self.boxes, recent: []) { chosen.append($0) }
        picker.pickerField.stringValue = "bills"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(picker.matches.first == Self.boxes[0])
        let editor = NSTextView()
        _ = picker.control(picker.pickerField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = picker.control(picker.pickerField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen == [Self.boxes[1]])
        picker.prepare(mailboxes: Self.boxes, recent: []) { chosen.append($0) }
        _ = picker.control(picker.pickerField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        _ = picker.control(picker.pickerField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen.count == 1)
    }

    @Test(arguments: [
        ("abc@example.com", "message://%3Cabc@example.com%3E"),
        ("<abc@example.com>", "message://%3Cabc@example.com%3E"),
        ("a+b/c%d e@x", "message://%3Ca%2Bb%2Fc%25d%20e@x%3E"),
    ])
    func messageLinks(id: String, expected: String) {
        #expect(MailLinks.link(forMessageID: id)?.absoluteString == expected)
    }

    @Test func noLinkWithoutAnID() {
        #expect(MailLinks.link(forMessageID: "") == nil)
        #expect(MailLinks.link(forMessageID: "<>") == nil)
    }

    struct FakeScripting: MailScripting {
        var selected: [MailSend.Selected]
        func selectedMessages() -> [MailSend.Selected] { selected }
    }

    /// The link goes on the clipboard only for exactly one selected message.
    @Test func copiesTheLinkOfOneSelectedMessage() {
        let board = NSPasteboard(name: NSPasteboard.Name("OpenShelfTests.link.\(UUID())"))
        board.clearContents()
        board.setString("before", forType: .string)
        MailLinks.copyLink(scripting: FakeScripting(selected: []), pasteboard: board, tell: { _ in })
        #expect(board.string(forType: .string) == "before")
        MailLinks.copyLink(scripting: FakeScripting(selected: [.init(id: "a@x", subject: "A"), .init(id: "b@x", subject: "B")]), pasteboard: board, tell: { _ in })
        #expect(board.string(forType: .string) == "before")
        MailLinks.copyLink(scripting: FakeScripting(selected: [.init(id: "a@x", subject: "A")]), pasteboard: board, tell: { _ in })
        #expect(board.string(forType: .string) == "message://%3Ca@x%3E")
        board.releaseGlobally()
    }
}
