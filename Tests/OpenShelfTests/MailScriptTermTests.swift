import Foundation
import Testing
@testable import OpenShelf

/// Every variable in the Mail scripts must stay a variable inside a tell to Mail: a plain
/// word such as scope, name, id or result is Mail's own term there, and the scripts failed
/// with -1700 and -10006 because of it (2026-11-20). Each script is compiled with osacompile
/// (Mail's dictionary is read from its bundle; nothing is sent to Mail and nothing runs),
/// and each name it assigns is probed the same way.
struct MailScriptTermTests {
    static var scripts: [(String, String)] {
        [("list mailboxes", AppleScriptMailFiling.listingSource),
         ("selected messages", MailScripts.selectedMessages),
         ("selected senders", MailScripts.selectedSenders),
         ("selection state", MailScripts.selectionState),
         ("move selection", MailScripts.move(to: "mailbox \"Archive\" of account \"Work\""))]
    }

    static let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelfTests/osa-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Compiles `source`; the compiled bytes, or nil when it doesn't compile.
    static func compile(_ source: String, as name: String) -> Data? {
        // A file of its own per compile: test cases run in parallel.
        let unique = "\(name)-\(UUID().uuidString)"
        let input = folder.appendingPathComponent("\(unique).applescript"), output = folder.appendingPathComponent("\(unique).scpt")
        try? source.write(to: input, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", output.path, input.path]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? try? Data(contentsOf: output) : nil
    }

    /// Whether `word`, assigned inside a tell to Mail, is taken as one of Mail's terms: it
    /// doesn't compile as a variable, or compiles differently from the forced variable
    /// |word| (lowercase words), or its name isn't stored (camel-case words, whose stored
    /// case differs with bars).
    static func isMailTerm(_ word: String) -> Bool {
        let plain = "tell application id \"com.apple.mail\"\nset \(word) to 1\nget \(word)\nend tell\n"
        guard let compiled = compile(plain, as: "plain-\(word)") else { return true }
        if word == word.lowercased() {
            let forced = compile(plain.replacingOccurrences(of: " \(word)", with: " |\(word)|"), as: "forced-\(word)")
            return compiled != forced
        }
        return compiled.range(of: Data(word.utf8)) == nil
    }

    /// The names a script assigns: set X to, repeat with X in/from, on error X number Y,
    /// and handler parameters.
    static func assignedNames(_ source: String) -> Set<String> {
        var names = Set<String>()
        let patterns = [#"\bset\s+([A-Za-z_]\w*)\s+to\b"#, #"\brepeat\s+with\s+([A-Za-z_]\w*)\s+(?:in|from)\b"#,
                        #"\bon\s+error\s+([A-Za-z_]\w*)\s+number"#, #"\bnumber\s+([A-Za-z_]\w*)\s*$"#]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) { names.insert(String(source[range])) }
            }
        }
        let handlers = try! NSRegularExpression(pattern: #"^\s*on\s+\w+\(([^)]*)\)"#, options: [.anchorsMatchLines])
        for match in handlers.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            if let range = Range(match.range(at: 1), in: source) {
                source[range].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.forEach { names.insert($0) }
            }
        }
        return names
    }

    @Test(arguments: scripts.map(\.0))
    func everyMailScriptCompilesAndItsVariablesAreNotMailTerms(name: String) throws {
        let source = try #require(Self.scripts.first { $0.0 == name }?.1)
        #expect(Self.compile(source, as: name.replacingOccurrences(of: " ", with: "-")) != nil, "\(name) doesn't compile")
        let names = Self.assignedNames(source)
        #expect(!names.isEmpty)
        for word in names.sorted() {
            #expect(!Self.isMailTerm(word), "\(name): \(word) is one of Mail's terms inside a tell")
        }
    }

    /// The probe itself: scope, name, id and result are Mail terms; os-names are not.
    @Test func theProbeKnowsMailsTerms() {
        for term in ["scope", "name", "id", "result"] { #expect(Self.isMailTerm(term), "\(term)") }
        for word in ["osOut", "osScopeName", "out", "m"] { #expect(!Self.isMailTerm(word), "\(word)") }
    }
}
