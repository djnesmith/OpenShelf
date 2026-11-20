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
    @Test func copiesTheLinkOfOneSelectedMessage() async {
        let board = NSPasteboard(name: NSPasteboard.Name("OpenShelfTests.link.\(UUID())"))
        board.clearContents()
        board.setString("before", forType: .string)
        await MailLinks.copyLink(scripting: FakeScripting(selected: []), pasteboard: board, tell: { _, _ in })
        #expect(board.string(forType: .string) == "before")
        await MailLinks.copyLink(scripting: FakeScripting(selected: [.init(id: "a@x", subject: "A"), .init(id: "b@x", subject: "B")]), pasteboard: board, tell: { _, _ in })
        #expect(board.string(forType: .string) == "before")
        await MailLinks.copyLink(scripting: FakeScripting(selected: [.init(id: "a@x", subject: "A")]), pasteboard: board, tell: { _, _ in })
        #expect(board.string(forType: .string) == "message://%3Ca@x%3E")
        board.releaseGlobally()
    }

    /// A success toast goes quickly; one to read stays longer (David, 2026-11-20).
    @Test func successToastsAreShort() async {
        #expect(MailHelpers.successToast == .milliseconds(1500))
        #expect(MailHelpers.problemToast >= .seconds(4))
        let board = NSPasteboard(name: NSPasteboard.Name("OpenShelfTests.linkToast.\(UUID())"))
        var shown: [(String, Duration)] = []
        await MailLinks.copyLink(scripting: FakeScripting(selected: [.init(id: "a@x", subject: "A")]), pasteboard: board, tell: { shown.append(($0.title, $1)) })
        await MailLinks.copyLink(scripting: FakeScripting(selected: []), pasteboard: board, tell: { shown.append(($0.title, $1)) })
        #expect(shown.map(\.0) == ["Link copied", "No link copied"])
        #expect(shown.map(\.1) == [MailHelpers.successToast, .seconds(3)])
        board.releaseGlobally()
    }

    /// Mail script errors are told as they are: the permission and where to give it, or the
    /// error number; quoted names never reach the log (2026-11-20: "Mail listed no
    /// mailboxes (Automation permission?)" guessed wrong).
    @Test func mailScriptProblemsSayWhatHappened() {
        #expect(MailScript.problem(.init(text: "x", error: nil, message: nil)) == nil)
        let denied = MailScript.problem(.init(text: nil, error: -1743, message: "Not authorized"))
        #expect(denied?.title == "Allow OpenShelf to control Mail")
        #expect(denied?.subtitle == "System Settings › Privacy & Security › Automation › OpenShelf › Mail")
        #expect(MailScript.problem(.init(text: nil, error: -1712, message: nil))?.subtitle.hasPrefix("Error -1712, Mail was slow to answer") == true)
        #expect(MailScript.problem(.init(text: nil, error: -1728, message: nil))?.subtitle.hasPrefix("Error -1728") == true)
        #expect(MailScript.scrubbed("Can’t get mailbox “Secret Project” of account \"Work\".") == "Can’t get mailbox “…” of account “…”.")
    }

    /// Toast subtitles wrap to two lines and are cut at the end; a path is cut in the middle.
    @Test func toastsCutPathsInTheMiddleAndSentencesAtTheEnd() {
        #expect(ToastText.looksLikePath("~/Library/Logs/OpenShelf/send.log"))
        #expect(ToastText.looksLikePath("/Users/x/file.pdf"))
        #expect(ToastText.looksLikePath("Inbox/Receipts"))
        #expect(!ToastText.looksLikePath("Mail returned no mailboxes (account 2 -1712)"))
        #expect(!ToastText.looksLikePath("System Settings › Privacy & Security › Automation › OpenShelf › Mail"))
    }

    /// A listing that arrives late: shown when the picker it was for is still open; dropped
    /// when the picker closed or opened again; a failed one (a timeout) keeps this
    /// session's list, and fails only with nothing to show (2026-11-20).
    @Test func listingsArriveLateDroppedOrFailed() {
        let boxes = Array(Self.boxes.prefix(2))
        let cached = Array(Self.boxes.suffix(2))
        #expect(MailFiling.arrival(boxes: boxes, for: 3, current: 3, pickerOpen: true, cached: nil) == .show(boxes))
        #expect(MailFiling.arrival(boxes: boxes, for: 3, current: 3, pickerOpen: false, cached: nil) == .dropped)
        #expect(MailFiling.arrival(boxes: boxes, for: 3, current: 4, pickerOpen: true, cached: nil) == .dropped)
        // A timeout (nothing listed): the session's list stays, or the picker closes.
        #expect(MailFiling.arrival(boxes: [], for: 3, current: 3, pickerOpen: true, cached: cached) == .show(cached))
        #expect(MailFiling.arrival(boxes: [], for: 3, current: 3, pickerOpen: true, cached: nil) == .fail)
        #expect(MailFiling.arrival(boxes: [], for: 3, current: 3, pickerOpen: false, cached: nil) == .dropped)
    }

    /// The picker opens at once saying it is listing, then shows Mail's list when it comes.
    @Test func thePickerFillsWhenTheListArrives() {
        let picker = MailboxPicker()
        picker.prepare(mailboxes: [], recent: [], loading: true) { _ in }
        #expect(picker.rowTexts == ["Listing mailboxes…"])
        picker.update(mailboxes: Self.boxes)
        #expect(picker.rowTexts.count == Self.boxes.count)
        #expect(!picker.loading)
        picker.prepare(mailboxes: [], recent: [], loading: false) { _ in }
        #expect(picker.rowTexts == ["No mailbox matches"])
    }

    /// Mail scripts run on their own queue and come back with their text or error number.
    /// Plain AppleScript only: nothing here talks to Mail.
    @Test func scriptsRunOffTheMainThread() async {
        let ok = await MailScript.run("test", "return \"x\"")
        #expect(ok.text == "x")
        #expect(ok.error == nil)
        let bad = await MailScript.run("test", "this is not applescript (((")
        #expect(bad.error != nil)
        #expect(bad.text == nil)
    }

    /// Tests write their logs and state to a temporary folder, never David's real ones.
    @Test func testsNeverWriteTheRealLogs() {
        #expect(OpenShelfFiles.isTesting)
        let temp = FileManager.default.temporaryDirectory.path
        for url in [MailScript.logURL, KeysLog.fileURL, MailSend.logURL, SnoozeLog.fileURL, PreviewLog.fileURL, ActivityState.fileURL, MailCheck.fileURL] {
            #expect(url.path.hasPrefix(temp), "\(url.lastPathComponent)")
        }
    }

    /// The listing's log line from the shape Mail returns: per account, read and skipped
    /// with which error, accounts that are off; no names (2026-11-20).
    @Test func listingSummaryPerAccount() {
        let lines = ["\tInbox", "\tInbox/Old", "#DONE\tOn My Mac", "#OFF\taccount 1",
                     "Work\tINBOX", "#SKIP\taccount 2 -1700", "#DONE\taccount 2",
                     "#ERR\taccount 3 -1712"]
        #expect(MailFiling.listingSummary(lines) == "On My Mac 2 read; account 1 off; account 2 1 read, 1 skipped (-1700)")
        #expect(MailFiling.listingSummary([]) == "nothing listed")
    }

    /// The handler that walks mailboxes talks to Mail inside its own tell block: outside one,
    /// "mailboxes" compiled as a plain name and every account failed with -1700.
    @Test func theListingHandlerTalksToMail() throws {
        let source = AppleScriptMailFiling.listingSource
        let start = try #require(source.range(of: "on walk("))
        let end = try #require(source.range(of: "end walk"))
        let handler = source[start.upperBound..<end.lowerBound]
        #expect(handler.contains("tell application id \"com.apple.mail\""))
        #expect(handler.contains("on error number e"))
    }
}
