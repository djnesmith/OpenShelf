import Foundation

/// Reads and replaces GUI Emacs's region through emacsclient and the server
/// Emacs runs (Doom starts it in the GUI). The text always travels in files,
/// never inside the elisp, so nothing in it can be read as code.
enum EmacsClient {
    static let searchPaths = [
        "/opt/homebrew/bin/emacsclient", "/usr/local/bin/emacsclient", "/opt/local/bin/emacsclient",
        "/Applications/Emacs.app/Contents/MacOS/bin/emacsclient",
    ]

    static func executable(fileManager: FileManager = .default) -> URL? {
        searchPaths.first { fileManager.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// A Lisp string literal for `path`.
    static func lispString(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The selected window's region as (start end): evil's visual range when
    /// in visual state, else the active region, else nil.
    static let rangeForm = """
    (cond ((and (fboundp 'evil-visual-state-p) (evil-visual-state-p)) (list evil-visual-beginning evil-visual-end)) \
    ((use-region-p) (list (region-beginning) (region-end))))
    """

    /// Writes the region to `output` and answers "region", or "none".
    static func readForm(output: String) -> String {
        """
        (with-current-buffer (window-buffer (selected-window)) \
        (let ((range \(rangeForm))) \
        (if (and range (< (car range) (cadr range))) \
        (let ((coding-system-for-write 'utf-8-unix)) (write-region (car range) (cadr range) \(lispString(output)) nil 'silent) "region") \
        "none")))
        """
    }

    /// Replaces the region with the contents of `replacement` as one undoable
    /// change, if it still holds the contents of `original`; answers
    /// "replaced", "changed" or "none".
    static func replaceForm(original: String, replacement: String) -> String {
        """
        (with-current-buffer (window-buffer (selected-window)) \
        (let ((range \(rangeForm)) \
        (old (with-temp-buffer (let ((coding-system-for-read 'utf-8)) (insert-file-contents \(lispString(original)))) (buffer-string))) \
        (new (with-temp-buffer (let ((coding-system-for-read 'utf-8)) (insert-file-contents \(lispString(replacement)))) (buffer-string)))) \
        (cond ((not range) "none") \
        ((not (string= old (buffer-substring-no-properties (car range) (cadr range)))) "changed") \
        (t (let ((group (prepare-change-group)) (start (car range))) \
        (activate-change-group group) \
        (unwind-protect (progn (delete-region start (cadr range)) (goto-char start) (insert new)) \
        (undo-amalgamate-change-group group) (accept-change-group group)) \
        (when (and (fboundp 'evil-visual-state-p) (evil-visual-state-p)) (evil-exit-visual-state)) \
        (deactivate-mark) "replaced")))))
        """
    }

    enum Outcome: Equatable {
        case region(String)
        case replaced
        case noRegion
        case changed
        /// No emacsclient, no server, or Emacs didn't answer.
        case unavailable
    }

    /// What emacsclient printed: the form's string result, quoted.
    static func answer(in lines: [String]) -> String? {
        lines.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("\"") && $0.hasSuffix("\"") && $0.count >= 2 }
            .map { String($0.dropFirst().dropLast()) }
    }

    static func read(runner: ToolRunner = ProcessRunner.live, executable: URL? = executable()) async -> Outcome {
        guard let executable else { return .unavailable }
        return await withFolder { folder in
            let output = folder.appendingPathComponent("region.txt")
            guard let answer = await run(executable, readForm(output: output.path), runner: runner) else { return .unavailable }
            guard answer == "region" else { return .noRegion }
            guard let text = try? String(contentsOf: output, encoding: .utf8) else { return .unavailable }
            return .region(text)
        }
    }

    static func replace(_ original: String, with replacement: String, runner: ToolRunner = ProcessRunner.live, executable: URL? = executable()) async -> Outcome {
        guard let executable else { return .unavailable }
        return await withFolder { folder in
            let originalFile = folder.appendingPathComponent("original.txt")
            let replacementFile = folder.appendingPathComponent("replacement.txt")
            do {
                try original.write(to: originalFile, atomically: true, encoding: .utf8)
                try replacement.write(to: replacementFile, atomically: true, encoding: .utf8)
            } catch {
                return .unavailable
            }
            switch await run(executable, replaceForm(original: originalFile.path, replacement: replacementFile.path), runner: runner) {
            case "replaced": return .replaced
            case "changed": return .changed
            case "none": return .noRegion
            default: return .unavailable
            }
        }
    }

    private static func run(_ executable: URL, _ form: String, runner: ToolRunner) async -> String? {
        let lines = LineCollector()
        do {
            try await runner(ToolInvocation(executable: executable, arguments: ["--eval", form]), { lines.append($0) })
        } catch {
            return nil
        }
        return answer(in: lines.all)
    }

    private static func withFolder(_ body: (URL) async -> Outcome) async -> Outcome {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-emacs-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return .unavailable }
        defer { try? FileManager.default.removeItem(at: folder) }
        return await body(folder)
    }
}

/// Lines printed by a tool, gathered from its output callback.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}
