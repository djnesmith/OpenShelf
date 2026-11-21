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

    /// ⌃N and ⌃P move the highlight like ↓ and ↑, stop at the ends, and type nothing;
    /// Return then picks the highlighted row. Sent to the panel, never put on screen.
    @Test func controlNAndPMoveThePickerHighlight() {
        func key(_ chars: String, _ flags: NSEvent.ModifierFlags = .control) -> NSEvent {
            let typed = flags == .control ? String(UnicodeScalar(UInt8(chars.unicodeScalars.first!.value) & 0x1F)) : chars
            return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                    context: nil, characters: typed, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
        }
        #expect(MailboxPicker.step(for: key("n")) == 1)
        #expect(MailboxPicker.step(for: key("p")) == -1)
        #expect(MailboxPicker.step(for: key("n", [])) == nil)
        #expect(MailboxPicker.step(for: key("n", [.control, .shift])) == nil)
        #expect(MailboxPicker.step(for: key("n", [.control, .option])) == nil)
        #expect(MailboxPicker.step(for: key("n", .command)) == nil)
        #expect(MailboxPicker.step(for: key("j")) == nil)

        let picker = MailboxPicker()
        var chosen: [Box] = []
        let panel = picker.prepare(mailboxes: Self.boxes, recent: []) { chosen.append($0) }
        // The field has the keyboard, so a key the panel let through would reach it.
        panel.makeFirstResponder(picker.pickerField)
        let last = picker.matches.count - 1
        #expect(last >= 1)
        panel.sendEvent(key("p"))
        #expect(picker.highlighted == 0)
        panel.sendEvent(key("n"))
        #expect(picker.highlighted == 1)
        for _ in 0...last { panel.sendEvent(key("n")) }
        #expect(picker.highlighted == last)
        panel.sendEvent(key("p"))
        #expect(picker.highlighted == last - 1)
        #expect(picker.pickerField.stringValue.isEmpty)
        #expect(picker.rowTexts[last - 1].hasPrefix("▸ "))
        _ = picker.control(picker.pickerField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen == [picker.matches[last - 1]])
        // Opened again: back on the first row.
        picker.prepare(mailboxes: Self.boxes, recent: []) { _ in }
        #expect(picker.highlighted == 0)
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
        // Diagnostic markers are not mailboxes.
        #expect(MailFiling.listingSummary(["#STEP\tOn My Mac entered", "#STEP\tOn My Mac count 1", "\tInbox", "#DONE\tOn My Mac"]) == "On My Mac 1 read")
    }

    /// The handler that walks mailboxes talks to Mail inside its own tell block: outside one,
    /// "mailboxes" compiled as a plain name and every account failed with -1700.
    @Test func theListingHandlerTalksToMail() throws {
        let source = AppleScriptMailFiling.listingSource
        let start = try #require(source.range(of: "on osWalk("))
        let end = try #require(source.range(of: "end osWalk"))
        let handler = source[start.upperBound..<end.lowerBound]
        // Mail is asked in one-line tells; the text is built outside them.
        #expect(handler.contains("tell application id \"com.apple.mail\" to set osBoxName to name of osBox"))
        #expect(handler.contains("tell application id \"com.apple.mail\" to set osChildren to mailboxes of osBox"))
        #expect(handler.contains("on error osMessage number osNumber"))
    }

    /// A move counts only from where Mail shows the messages afterwards (2026-11-20: a
    /// move back to the Inbox reported success and left the message in both places).
    @Test func movesAreJudgedFromWhereTheMessagesAre() {
        #expect(MailFiling.moveOutcome(total: 1, inSource: 0, inDestination: 1) == .moved)
        #expect(MailFiling.moveOutcome(total: 1, inSource: 1, inDestination: 1) == .copied)
        #expect(MailFiling.moveOutcome(total: 1, inSource: 1, inDestination: 0) == .notMoved)
        #expect(MailFiling.moveOutcome(total: 3, inSource: 1, inDestination: 2) == .partial)
        #expect(MailFiling.moveOutcome(total: 0, inSource: 0, inDestination: 0) == .notMoved)
        let inbox = MailFiling.Mailbox(account: "Gmail", path: "INBOX")
        #expect(MailFiling.report(.moved, total: 1, to: inbox).title == "Moved to INBOX")
        #expect(MailFiling.report(.copied, total: 1, to: inbox) == MailFiling.MoveReport(outcome: .copied, title: "Copied to INBOX", subtitle: "1 message; still in the folder it was in"))
        #expect(MailFiling.report(.notMoved, total: 1, to: inbox, problem: "It is already there").subtitle == "It is already there")
    }

    /// The bulk listing's lines become paths in Mail's order, nested ones under their parent;
    /// an answer that doesn't line up gives nil (the full walk is used then).
    @Test func bulkListingPaths() {
        let lines = ["#L1\tINBOX", "#L1\tClients", "#L1\tReceipts",
                     "#L2\t2\tAcme", "#L2\t2\tGlobex", "#L3\t2\t1\t2026"]
        #expect(MailFiling.bulkPaths(lines) == ["INBOX", "Clients", "Clients/Acme", "Clients/Acme/2026", "Clients/Globex", "Receipts"])
        #expect(MailFiling.bulkPaths(["#MISALIGNED"]) == nil)
        #expect(MailFiling.bulkPaths(["#L1\tA", "#L2\t5\tB"]) == nil)
        #expect(MailFiling.bulkPaths([]) == [])
    }

    /// v offers the selected messages' one account (David, 2026-11-20); On My Mac after it;
    /// mixed accounts or nothing selected offer nothing.
    @Test func pickerScopeIsTheSelectionsAccount() {
        #expect(MailFiling.scope(of: ["Gmail", "Gmail"]) == .account("Gmail"))
        #expect(MailFiling.scope(of: ["", ""]) == .account(""))
        #expect(MailFiling.scope(of: ["Gmail", "Work"]) == .mixed)
        #expect(MailFiling.scope(of: ["Gmail", ""]) == .mixed)
        #expect(MailFiling.scope(of: []) == .nothingSelected)
        #expect(MailFiling.accountLines("Gmail\nGmail\n") == ["Gmail", "Gmail"])
        #expect(MailFiling.accountLines("\n") == [""])
        #expect(MailFiling.accountLines("") == [])
        let own = [MailFiling.Mailbox(account: "Gmail", path: "INBOX"), .init(account: "Gmail", path: "Clients/Acme")]
        let local = [MailFiling.Mailbox(account: "", path: "Old")]
        #expect(MailFiling.pickerList(account: "Gmail", own: own, local: local) == own + local)
        #expect(MailFiling.pickerList(account: "", own: local, local: local) == local)
    }

    /// The lists are kept by account across launches.
    @Test func mailboxListsAreKeptByAccount() {
        let defaults = UserDefaults(suiteName: "OpenShelfTests.filingCache.\(UUID())")!
        let cache = ["Gmail": [MailFiling.Mailbox(account: "Gmail", path: "INBOX")], "": [.init(account: "", path: "Old")]]
        MailFiling.saveCache(cache, defaults)
        #expect(MailFiling.loadCache(defaults) == cache)
        #expect(MailFiling.loadCache(UserDefaults(suiteName: "OpenShelfTests.empty.\(UUID())")!).isEmpty)
    }

    /// Mail's answer to the move: the folder that didn't resolve, nothing selected, or the
    /// per-message counts. Anything else claims nothing.
    @Test func moveAnswersAreRead() {
        #expect(MailFiling.moveResult("#NOFOLDER\t-1728\t1\t1\n") == .folderNotFound(error: -1728, level: 1, of: 1))
        #expect(MailFiling.moveResult("#NOFOLDER\t-1728\t2\t3") == .folderNotFound(error: -1728, level: 2, of: 3))
        #expect(MailFiling.moveResult("#NONE") == .nothingSelected)
        #expect(MailFiling.moveResult("#RESULT\t0\t0\t4\t0\t0\t0\tINBOX") == .counted(moved: 0, left: 0, stayed: 4, unread: 0, fellBack: 0, failed: 0, source: "INBOX"))
        #expect(MailFiling.moveResult("#RESULT\t1\t2\t0\t0\t1\t0\t") == .counted(moved: 1, left: 2, stayed: 0, unread: 0, fellBack: 1, failed: 0, source: ""))
        #expect(MailFiling.moveResult("#RESULT\t1\t0\t0\t0\t0\t0\tA\tB") == .counted(moved: 1, left: 0, stayed: 0, unread: 0, fellBack: 0, failed: 0, source: "A\tB"))
        #expect(MailFiling.moveResult("#RESULT\t0\t4\t0\t0\t0\tINBOX") == .unreadable)
        #expect(MailFiling.moveResult("#RESULT\tx\t0\t0\t0\t0\t0\t") == .unreadable)
        #expect(MailFiling.moveResult("") == .unreadable)
        #expect(MailFiling.moveResult("#MOVED\t4\t0") == .unreadable)
    }

    /// The toast says only what Mail showed (2026-11-20: "moved 4" when the 4 were still in
    /// the Inbox). "Moved" only when every message left where it was; still there, "Sent",
    /// since whether it reached the folder isn't searched for. The log line has no names.
    @MainActor @Test func moveToastsSayWhatMailShows() {
        let info = MailFiling.Mailbox(account: "Gmail", path: "[Info]")
        func counted(_ moved: Int, _ left: Int, _ stayed: Int, _ unread: Int = 0, failed: Int = 0) -> MailFiling.MoveResult {
            .counted(moved: moved, left: left, stayed: stayed, unread: unread, fellBack: 0, failed: failed, source: "INBOX")
        }
        #expect(counted(0, 0, 4).report(to: info) == MailFiling.MoveReport(outcome: .copied, title: "Sent to [Info]", subtitle: "4 messages; still in the Inbox"))
        #expect(!counted(0, 0, 4).logLine.contains("INBOX"))
        #expect(!counted(0, 0, 4).logLine.contains("Info"))
        #expect(counted(4, 0, 0).report(to: info) == MailFiling.MoveReport(outcome: .moved, title: "Moved to [Info]", subtitle: "4 messages"))
        #expect(counted(2, 2, 0).report(to: info).outcome == .moved)
        #expect(counted(0, 1, 0).report(to: info).outcome == .moved)
        #expect(counted(1, 0, 1).report(to: info) == MailFiling.MoveReport(outcome: .partial, title: "Partly moved to [Info]", subtitle: "1 moved, 1 still in the Inbox"))
        #expect(counted(0, 0, 1, 1).report(to: info).outcome == .partial)
        #expect(counted(0, 0, 2, failed: 2).report(to: info) == MailFiling.MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Mail refused the move"))
        #expect(counted(0, 0, 2, failed: 1).report(to: info).outcome == .partial)
        #expect(counted(0, 0, 0).report(to: info).outcome == .notMoved)
        let missing = MailFiling.MoveResult.folderNotFound(error: -1728, level: 1, of: 1)
        #expect(missing.report(to: info) == MailFiling.MoveReport(outcome: .notMoved, title: "Not moved", subtitle: "Can't find that folder in Mail"))
        #expect(missing.logLine.contains("level 1 of 1"))
        #expect(missing.logLine.contains("-1728"))
        #expect(MailFiling.MoveResult.unreadable.report(to: info).outcome == .notMoved)
        #expect(MailFiling.folderName("Archive") == "Archive")
        #expect(MailFiling.folderName("") == "the folder it was in")
    }

    /// The script proves the folder exists, name by name, before touching the selection; it
    /// sets each message's mailbox, runs the move command only when that raises an error,
    /// asks each message for its own mailbox afterwards, never searches a mailbox (a
    /// "whose" search held Mail at 100% CPU, 2026-11-20), never waits on purpose, and never
    /// deletes anything.
    @Test func theMoveChecksTheFolderFirstAndStaysLight() throws {
        let script = MailScripts.moveAndCheck(account: "Gmail", chain: ["Clients", "Acme"])
        let check = try #require(script.range(of: "#NOFOLDER"))
        let selection = try #require(script.range(of: "selection as list"))
        #expect(check.lowerBound < selection.lowerBound)
        let set = try #require(script.range(of: "set mailbox of osMessage to osBox"))
        let move = try #require(script.range(of: "move osMessage to osBox"))
        #expect(set.lowerBound < move.lowerBound)
        let flat = script.replacingOccurrences(of: " ", with: "")
        #expect(flat.contains("onerror\nsetosFellBacktoosFellBack+1\ntry\ntellapplicationid\"com.apple.mail\"tomoveosMessagetoosBox"))
        #expect(flat.contains("settoosNowtonameofmailboxofosMessage") || flat.contains("tosetosNowtonameofmailboxofosMessage"))
        #expect(!script.lowercased().contains("whose"))
        #expect(!script.lowercased().contains("delay"))
        #expect(!script.lowercased().contains("delete"))
        #expect(script.contains("with timeout of 5 seconds"))
        #expect(script.contains("set osChain to {\"Clients\", \"Acme\"}"))
        #expect(script.contains("mailbox (item 1 of osChain) of account \"Gmail\""))
        #expect(MailScripts.moveAndCheck(account: "", chain: ["Old"]).contains("set osBox to mailbox (item 1 of osChain)\n"))
    }

    /// A move picked while another is still running is refused, not queued behind it.
    @MainActor @Test func oneFilingAtATime() async {
        final class SlowMail: MailFilingScripting {
            func mailboxes() async -> [MailFiling.Mailbox] { [] }
            func selectionAccounts() async -> [String] { [] }
            func mailboxes(of account: String) async -> [MailFiling.Mailbox] { [] }
            var lastProblem: (title: String, subtitle: String)? { nil }
            func move(to mailbox: MailFiling.Mailbox) async -> MailFiling.MoveReport {
                try? await Task.sleep(for: .milliseconds(300))
                return MailFiling.MoveReport(outcome: .moved, title: "Moved", subtitle: "")
            }
        }
        let mail = SlowMail(), box = MailFiling.Mailbox(account: "Gmail", path: "[Info]")
        let first = Task { @MainActor in await MailFiling.file(box, with: mail) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await MailFiling.file(box, with: mail) == MailFiling.stillFiling)
        #expect(await first.value.outcome == .moved)
        #expect(await MailFiling.file(box, with: mail).outcome == .moved)
    }

    /// Mailbox names with brackets, slashes, quotes and other characters, top level and
    /// nested, survive the listing, the saved list, the folder chain and the script, and
    /// each script compiles. The regression: a top-level Gmail mailbox named "[Info]".
    nonisolated static let oddNames = ["[Info]", "(Receipts)", "a/b", "back\\slash", "say \"hi\"", "it's", "R&D", "Café ☕︎ 日本", "[x]/(y)\\z"]

    @Test func infoAtTheTopLevel() throws {
        let paths = try #require(MailFiling.bulkPaths(["#L1\tINBOX", "#L1\t[Info]"]))
        #expect(paths == ["INBOX", "[Info]"])
        let info = MailFiling.Mailbox(account: "Gmail", path: paths[1])
        #expect(info.chain == ["[Info]"])
        #expect(info.display == "[Info] — Gmail")
        let script = MailScripts.moveAndCheck(account: info.account, chain: info.chain)
        #expect(script.contains("set osChain to {\"[Info]\"}"))
        #expect(MailScriptTermTests.compile(script, as: "info") != nil)
    }

    @Test(arguments: oddNames) func oddNamesSurviveEveryStep(name: String) throws {
        let parent = "Parent [1]"
        let lines = ["#L1\t\(name)", "#L1\t\(parent)", "#L2\t2\t\(name)", "#L3\t2\t1\t\(name)"]
        let paths = try #require(MailFiling.bulkPaths(lines))
        #expect(paths.count == 4)
        let boxes = paths.map { MailFiling.Mailbox(account: "Gmail", path: $0) }
        #expect(boxes.map(\.chain) == [[name], [parent], [parent, name], [parent, name, name]])
        #expect(boxes[0].shown == name)
        #expect(boxes[2].shown == "\(parent)/\(name)")
        let defaults = UserDefaults(suiteName: "OpenShelfTests.oddNames.\(UUID())")!
        MailFiling.saveCache(["Gmail": boxes], defaults)
        #expect(MailFiling.loadCache(defaults)["Gmail"]?.map(\.chain) == boxes.map(\.chain))
        #expect(MailScripts.specifier(account: "Gmail", path: name).hasPrefix("mailbox \(MailScripts.quoted(name)) of account"))
        for box in [boxes[0], boxes[3]] {
            let script = MailScripts.moveAndCheck(account: box.account, chain: box.chain)
            #expect(script.contains("set osChain to {" + box.chain.map(MailScripts.quoted).joined(separator: ", ") + "}"))
            #expect(MailScriptTermTests.compile(script, as: "odd") != nil, "didn't compile for \(box.chain)")
        }
        // The full walk's escape, run by AppleScript itself (no app is asked), gives the same
        // path as the Swift side.
        #expect(Self.walkEscape(name) == MailFiling.joinPath([name]))
    }

    /// Runs the listing script's osEscape handler with osascript; nothing else runs.
    static func walkEscape(_ name: String) -> String? {
        let source = AppleScriptMailFiling.listingSource
        guard let start = source.range(of: "on osEscape(osText)"), let end = source.range(of: "end osEscape") else { return nil }
        let handler = String(source[start.lowerBound..<end.upperBound])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", handler + "\nreturn osEscape(" + MailScripts.quoted(name) + ")"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}
