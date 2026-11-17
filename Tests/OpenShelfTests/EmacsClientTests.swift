import Foundation
import Testing
@testable import OpenShelf

struct EmacsClientTests {
    static let emacsclient = URL(fileURLWithPath: "/opt/homebrew/bin/emacsclient")

    @Test func readSendsOneEvalAndReadsTheRegionFile() async throws {
        let fake = FakeToolRunner { invocation in
            #expect(invocation.arguments.first == "--eval")
            let form = try #require(invocation.arguments.last)
            let path = try #require(form.range(of: #""/[^"]*region\.txt""#, options: .regularExpression)).lowerBound
            let end = form[form.index(after: path)...].firstIndex(of: "\"")!
            try "the region".write(toFile: String(form[form.index(after: path)..<end]), atomically: true, encoding: .utf8)
            return ["\"region\""]
        }
        #expect(await EmacsClient.read(runner: fake.runner, executable: Self.emacsclient) == .region("the region"))
        #expect(fake.invocations.count == 1)
        #expect(fake.invocations.first?.executable == Self.emacsclient)
    }

    @Test(arguments: [(["\"none\""], EmacsClient.Outcome.noRegion), (["\"unexpected\""], .noRegion), (["noise"], .unavailable)])
    func readOutcomes(lines: [String], expected: EmacsClient.Outcome) async {
        let fake = FakeToolRunner { _ in lines }
        #expect(await EmacsClient.read(runner: fake.runner, executable: Self.emacsclient) == expected)
    }

    @Test func noServerOrNoClientIsUnavailable() async {
        struct NoSocket: Error {}
        let failing = FakeToolRunner { _ in throw NoSocket() }
        #expect(await EmacsClient.read(runner: failing.runner, executable: Self.emacsclient) == .unavailable)
        #expect(await EmacsClient.read(runner: failing.runner, executable: nil) == .unavailable)
        #expect(await EmacsClient.replace("a", with: "b", runner: failing.runner, executable: Self.emacsclient) == .unavailable)
    }

    @Test(arguments: [("\"replaced\"", EmacsClient.Outcome.replaced), ("\"changed\"", .changed), ("\"none\"", .noRegion)])
    func replaceOutcomes(line: String, expected: EmacsClient.Outcome) async {
        let fake = FakeToolRunner { _ in [line] }
        #expect(await EmacsClient.replace("old", with: "new", runner: fake.runner, executable: Self.emacsclient) == expected)
    }

    @Test func textNeverAppearsInTheElisp() async throws {
        let fake = FakeToolRunner { _ in ["\"replaced\""] }
        _ = await EmacsClient.replace("(delete-file \"x\")", with: "\") (kill-emacs) (\"", runner: fake.runner, executable: Self.emacsclient)
        let form = try #require(fake.invocations.first?.arguments.last)
        #expect(!form.contains("kill-emacs"))
        #expect(!form.contains("delete-file"))
    }

    /// The elisp itself, in a throwaway batch Emacs (-Q: no config, no
    /// server, its own buffer), since GUI Emacs isn't necessarily running.
    @Test(.enabled(if: RealToolTests.enabled && FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/emacs")))
    func elispReadsAndReplacesAsOneUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-emacs-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let region = folder.appendingPathComponent("region.txt").path
        let original = folder.appendingPathComponent("original.txt").path
        let replacement = folder.appendingPathComponent("replacement.txt").path
        try "two".write(toFile: original, atomically: true, encoding: .utf8)
        try "TWO ✓".write(toFile: replacement, atomically: true, encoding: .utf8)
        let script = """
        (progn
          (let ((buf (get-buffer-create "openshelf-test")))
            (set-window-buffer (selected-window) buf)
            (with-current-buffer buf
              (insert "one two three") (undo-boundary)
              (transient-mark-mode 1) (goto-char 5) (set-mark 5) (goto-char 8)))
          (princ (format "READ:%s\\n" \(EmacsClient.readForm(output: region))))
          (princ (format "REPLACE:%s\\n" \(EmacsClient.replaceForm(original: original, replacement: replacement))))
          (with-current-buffer "openshelf-test"
            (princ (format "AFTER:%s\\n" (buffer-string)))
            (undo-boundary) (setq last-command nil) (undo)
            (princ (format "UNDONE:%s\\n" (buffer-string))))
          (with-current-buffer "openshelf-test" (set-mark 5) (goto-char 8) (activate-mark))
          (princ (format "STALE:%s\\n" \(EmacsClient.replaceForm(original: replacement, replacement: replacement)))))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/emacs")
        process.arguments = ["--batch", "-Q", "--eval", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output.contains("READ:region"), "\(output)")
        #expect(try String(contentsOfFile: region, encoding: .utf8) == "two")
        #expect(output.contains("REPLACE:replaced"), "\(output)")
        #expect(output.contains("AFTER:one TWO ✓ three"), "\(output)")
        #expect(output.contains("UNDONE:one two three"), "\(output)")
        #expect(output.contains("STALE:changed"), "\(output)")
    }
}
