import Foundation
import Testing
@testable import OpenShelf

struct PrettyPrintTests {
    static let tools = ExternalTools.detect(ignoring: [])
    static let none = ExternalTools(ffmpeg: nil, cwebp: nil)

    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-pretty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func file(_ name: String, _ text: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    static func has(_ formatter: PrettyPrint.Formatter) -> Bool {
        PrettyPrint.executable(for: formatter, tools: tools.formatters) != nil
    }

    @Test func eachLanguageHasItsFormatter() {
        #expect(PrettyPrint.formatter(forExtension: "JSON") == .deno("json"))
        #expect(PrettyPrint.formatter(forExtension: "mjs") == .deno("js"))
        #expect(PrettyPrint.formatter(forExtension: "yml") == .deno("yaml"))
        #expect(PrettyPrint.formatter(forExtension: "markdown") == .deno("md"))
        #expect(PrettyPrint.formatter(forExtension: "edn") == .cljfmt)
        #expect(PrettyPrint.formatter(forExtension: "py") == .ruff)
        #expect(PrettyPrint.formatter(forExtension: "sh") == .shfmt)
        #expect(PrettyPrint.formatter(forExtension: "swift") == .swiftFormat)
        #expect(PrettyPrint.formatter(forExtension: "xml") == .xmllint)
        #expect(PrettyPrint.formatter(forExtension: "sql") == .pgFormat)
        #expect(PrettyPrint.formatter(forExtension: "mm") == .clangFormat("source.mm"))
        #expect(PrettyPrint.formatter(forExtension: "go") == .gofmt)
        #expect(PrettyPrint.formatter(forExtension: "rs") == .rustfmt)
        #expect(PrettyPrint.formatter(forExtension: "txt") == nil)
        #expect(PrettyPrint.formatter(forExtension: "zsh") == nil)
    }

    @Test func toolsWheelOffersItOnlyWithTheFormatter() {
        let python = URL(fileURLWithPath: "/tmp/a.py")
        let ruff = URL(fileURLWithPath: "/opt/homebrew/bin/ruff")
        var withRuff = Self.none
        withRuff.formatters.ruff = ruff
        #expect(FileTool.available(for: [python], tools: withRuff) == [.prettyPrint])
        #expect(FileTool.available(for: [python], tools: Self.none) == [])
        // Every file has to be formattable.
        #expect(FileTool.available(for: [python, URL(fileURLWithPath: "/tmp/a.txt")], tools: withRuff) == [])
        #expect(FileTool.prettyPrint.title == "Pretty Print")
    }

    /// No argument names the file, and each formatter is given its config
    /// rather than left to search for one.
    @Test func formattersNeverSeeThePathAndGetAnExplicitConfig() {
        let folder = URL(fileURLWithPath: "/tmp/openshelf-format-x")
        let all: [PrettyPrint.Formatter] = [.deno("ts"), .cljfmt, .ruff, .shfmt, .swiftFormat, .xmllint, .pgFormat, .clangFormat("source.c"), .gofmt, .rustfmt]
        for formatter in all {
            let arguments = PrettyPrint.arguments(for: formatter, folder: folder)
            #expect(arguments.allSatisfy { !$0.hasPrefix("/") || $0.hasPrefix(folder.path) }, "\(formatter): \(arguments)")
        }
        #expect(PrettyPrint.arguments(for: .deno("ts"), folder: folder).contains("--no-config"))
        #expect(PrettyPrint.arguments(for: .deno("ts"), folder: folder).contains("--use-tabs=false"))
        #expect(PrettyPrint.arguments(for: .ruff, folder: folder).contains("--isolated"))
        #expect(PrettyPrint.arguments(for: .pgFormat, folder: folder).contains("--no-rcfile"))
        #expect(PrettyPrint.arguments(for: .clangFormat("source.c"), folder: folder).contains("--style=LLVM"))
        #expect(PrettyPrint.arguments(for: .xmllint, folder: folder).contains("--nonet"))
        #expect(!PrettyPrint.arguments(for: .xmllint, folder: folder).contains("--noent"))
        #expect(PrettyPrint.arguments(for: .swiftFormat, folder: folder).contains("--configuration"))
        #expect(PrettyPrint.arguments(for: .cljfmt, folder: folder).contains("/tmp/openshelf-format-x/cljfmt.edn"))
        #expect(PrettyPrint.arguments(for: .rustfmt, folder: folder).contains("/tmp/openshelf-format-x/rustfmt.toml"))
    }

    @Test func trailingBlankLinesDontCount() {
        #expect(PrettyPrint.isSame(Data("a\n\n".utf8), Data("a\n".utf8)))
        #expect(!PrettyPrint.isSame(Data("a b\n".utf8), Data("a  b\n".utf8)))
    }

    @Test func alreadyFormattedToast() {
        let outcome = SaveOutcome(saved: [], unchanged: 1, unchangedLabel: "already formatted")
        #expect(outcome.title == "Nothing saved")
        #expect(outcome.subtitle == "Already formatted")
    }

    /// Messy input, and what the formatter's output must contain.
    static let samples: [(name: String, input: String, expected: String)] = [
        ("a.ts", "function f(a,b){return a+b}\n", "function f(a, b) {\n  return a + b;\n}\n"),
        ("a.json", "{\"b\":1,\"a\":[1,2],\"b\":2}\n", "{ \"b\": 1, \"a\": [1, 2], \"b\": 2 }\n"),
        ("a.yaml", "a:   [1,2]\n", "a: [1, 2]\n"),
        ("a.md", "#  Title\n*  item\n", "# Title\n\n- item\n"),
        ("a.html", "<div><p>x</p></div>\n", "<div>\n  <p>x</p>\n</div>\n"),
        ("a.clj", "(defn f [a]\n(+ a 1))\n", "(defn f [a]\n  (+ a 1))\n"),
        ("a.py", "def f(a,b):\n  return a+b\n", "def f(a, b):\n    return a + b\n"),
        ("a.sh", "if true; then\necho hi\nfi\n", "if true; then\n  echo hi\nfi\n"),
        ("a.swift", "func f(){\nreturn}\n", "func f() {\n  return\n}\n"),
        ("a.xml", "<a><b>x</b></a>", "<a>\n  <b>x</b>\n</a>\n"),
        ("a.sql", "select a, b from t where x = 1;\n", "SELECT\n    a,\n    b\nFROM\n    t\nWHERE\n    x = 1;\n"),
        ("a.c", "int f(int a){if(a){return 1;}return 0;}\n", "int f(int a) {\n  if (a) {\n    return 1;\n  }\n  return 0;\n}\n"),
        ("a.go", "package main\nfunc main(){\nprintln(1)}\n", "package main\n\nfunc main() {\n\tprintln(1)\n}\n"),
        ("a.rs", "fn main(){println!(\"x\");}\n", "fn main() {\n    println!(\"x\");\n}\n"),
    ]

    @Test(arguments: samples.map(\.name))
    func formatsIntoANewFileNextToTheOriginal(name: String) async throws {
        let sample = try #require(Self.samples.first { $0.name == name })
        let formatter = try #require(PrettyPrint.formatter(forExtension: URL(fileURLWithPath: name).pathExtension))
        guard Self.has(formatter) else { return }
        let folder = try workspace()
        let source = try file(name, sample.input, in: folder)

        let output = try #require(try await PrettyPrint.format(source, tools: Self.tools))
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        #expect(output.lastPathComponent == "\(stem).formatted.\(ext)")
        let text = try String(contentsOf: output, encoding: .utf8)
        #expect(text.contains(sample.expected), "\(text)")
        #expect(try String(contentsOf: source, encoding: .utf8) == sample.input)

        // Formatting again finds nothing to change and saves nothing.
        let before = try names(in: folder)
        #expect(try await PrettyPrint.format(output, tools: Self.tools) == nil)
        #expect(try names(in: folder) == before)
    }

    @Test(.enabled(if: has(.ruff))) func aNameClashGetsACounter() async throws {
        let folder = try workspace()
        let source = try file("a.py", "x=1\n", in: folder)
        let first = try #require(try await PrettyPrint.format(source, tools: Self.tools))
        let second = try #require(try await PrettyPrint.format(source, tools: Self.tools))
        #expect(first.lastPathComponent == "a.formatted.py")
        #expect(second.lastPathComponent == "a.formatted 2.py")
    }

    @Test(.enabled(if: has(.ruff) && has(.deno("ts")) && has(.rustfmt) && has(.gofmt)))
    func aFormatterErrorSavesNothing() async throws {
        for (name, text, message) in [
            ("bad.py", "def (\n", "Expected an identifier"),
            ("bad.ts", "let x = {\n", "SyntaxError"),
            ("bad.rs", "fn main({\n", "unclosed delimiter"),
            ("bad.go", "package main\nfunc {\n", "expected"),
        ] {
            let folder = try workspace()
            let source = try file(name, text, in: folder)
            do {
                _ = try await PrettyPrint.format(source, tools: Self.tools)
                Issue.record("\(name) was formatted")
            } catch {
                #expect(error.localizedDescription.contains("couldn’t be formatted"), "\(error.localizedDescription)")
                #expect(error.localizedDescription.contains(message), "\(error.localizedDescription)")
            }
            #expect(try names(in: folder) == [name])
        }
    }

    /// Configs next to the file and in the folder above it change nothing:
    /// the same text formats the same in a clean folder and a planted one.
    /// A broken .cljfmt.edn would make cljfmt fail if it were read.
    @Test func configsNearTheFileAreIgnored() async throws {
        let clean = try workspace()
        let parent = try workspace()
        let planted = parent.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: planted, withIntermediateDirectories: true)
        let configs = [
            ".editorconfig": "[*]\nindent_style = tab\nindent_size = 8\n",
            "deno.json": #"{"fmt":{"indentWidth":8,"lineWidth":20}}"#,
            "ruff.toml": "line-length = 20\nindent-width = 8\n",
            ".clang-format": "IndentWidth: 8\nColumnLimit: 10\n",
            ".swift-format": #"{"indentation":{"spaces":8}}"#,
            ".cljfmt.edn": #"{:broken #"x}"#,
            ".pg_format": "keyword-case=0\nspaces=8\n",
            "rustfmt.toml": "hard_tabs = true\n",
        ]
        for (name, text) in configs {
            try text.write(to: planted.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try text.write(to: parent.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        for sample in Self.samples {
            let formatter = try #require(PrettyPrint.formatter(forExtension: URL(fileURLWithPath: sample.name).pathExtension))
            guard Self.has(formatter) else { continue }
            let input = sample.input.replacingOccurrences(of: "a+b", with: "aaaaaaaa+bbbbbbbbbb")
            let expected = try #require(try await PrettyPrint.format(try file(sample.name, input, in: clean), tools: Self.tools))
            let actual = try #require(try await PrettyPrint.format(try file(sample.name, input, in: planted), tools: Self.tools))
            #expect(try Data(contentsOf: actual) == Data(contentsOf: expected), "\(sample.name) followed a planted config")
        }
    }
}
