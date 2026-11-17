import Foundation
import Testing
@testable import OpenShelf

struct TextConversionTests {
    static let tools = ExternalTools.detect(ignoring: [])

    @Test func directPairsAreOneHop() {
        #expect(TextConversion.plan(from: .json, to: .yaml) == [.converter(from: .json, to: .yaml)])
        #expect(TextConversion.plan(from: .xml, to: .json) == [.converter(from: .xml, to: .json)])
        #expect(TextConversion.plan(from: .edn, to: .json) == [.converter(from: .edn, to: .json)])
        #expect(TextConversion.plan(from: .yaml, to: .edn) == [.converter(from: .yaml, to: .edn)])
        #expect(TextConversion.plan(from: .toml, to: .json) == [.yq(from: .toml, to: .json)])
        #expect(TextConversion.plan(from: .yaml, to: .toml) == [.yq(from: .yaml, to: .toml)])
    }

    @Test func otherPairsGoThroughJSON() {
        #expect(TextConversion.plan(from: .edn, to: .xml) == [.converter(from: .edn, to: .json), .converter(from: .json, to: .xml)])
        #expect(TextConversion.plan(from: .xml, to: .edn) == [.converter(from: .xml, to: .json), .converter(from: .json, to: .edn)])
        #expect(TextConversion.plan(from: .toml, to: .edn) == [.yq(from: .toml, to: .json), .converter(from: .json, to: .edn)])
        #expect(TextConversion.plan(from: .xml, to: .toml) == [.converter(from: .xml, to: .json), .yq(from: .json, to: .toml)])
    }

    @Test func everyPairHasAPlanEndingInTheTarget() {
        for source in DataTextFormat.allCases {
            for target in DataTextFormat.allCases where target != source {
                let plan = TextConversion.plan(from: source, to: target)
                #expect(!plan.isEmpty && plan.count <= 2, "\(source) → \(target)")
                switch plan.last {
                case .converter(_, let to), .yq(_, let to): #expect(to == target)
                case nil: Issue.record("no plan for \(source) → \(target)")
                }
            }
        }
    }

    @Test func tomlRunsYQInPlaceOnACopy() async throws {
        let yq = URL(fileURLWithPath: "/opt/homebrew/bin/yq")
        var tools = ExternalTools(ffmpeg: nil, cwebp: nil)
        tools.yq = yq
        let fake = FakeToolRunner { invocation in
            let path = try #require(invocation.arguments.last)
            try "{\"a\": 1}\n".write(toFile: path, atomically: true, encoding: .utf8)
            return []
        }
        let result = try await TextConversion.convert("a = 1", from: .toml, to: .json, tools: tools, runner: fake.runner)
        #expect(result == "{\"a\": 1}")
        let invocation = try #require(fake.invocations.first)
        #expect(invocation.executable == yq)
        #expect(Array(invocation.arguments.prefix(5)) == ["-p", "toml", "-o", "json", "-i"])
        #expect(invocation.arguments.last?.hasSuffix(".json") == true)
    }

    @Test func tomlWithoutYQSaysWhatIsMissing() async {
        await #expect(throws: MissingToolError.self) {
            try await TextConversion.convert("a = 1", from: .toml, to: .json, tools: ExternalTools(ffmpeg: nil, cwebp: nil))
        }
    }

    @Test func trailingNewlineFollowsTheSelection() {
        #expect(TextConversion.matchTrailingNewline("a\n\n", of: "x") == "a")
        #expect(TextConversion.matchTrailingNewline("a", of: "x\n") == "a\n")
        #expect(TextConversion.matchTrailingNewline("a\n", of: "x\n") == "a\n")
    }

    @Test func jsonReindentsWithoutDeno() throws {
        #expect(try TextConversion.prettyJSON(#"{"b":1,"a":[1,2]}"#) == "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1\n}")
        let pretty = "{\n  \"a\" : 1\n}"
        #expect(try TextConversion.prettyJSON(pretty) == nil)
    }

    // MARK: Real tools (OPENSHELF_TOOL_TESTS=1)

    @Test(.enabled(if: RealToolTests.enabled && tools.yq != nil && tools.jet != nil))
    func realDataConversions() async throws {
        let yaml = try await TextConversion.convert(#"{"name": "x", "n": 2}"#, from: .json, to: .yaml, tools: Self.tools)
        #expect(yaml == "name: x\nn: 2")
        let toml = try await TextConversion.convert("name: x\nn: 2", from: .yaml, to: .toml, tools: Self.tools)
        #expect(toml.contains("name = \"x\""))
        let xml = try await TextConversion.convert("{:name \"x\"}", from: .edn, to: .xml, tools: Self.tools)
        #expect(xml.contains("<name>x</name>"))
        let edn = try await TextConversion.convert("<r><a>1</a></r>", from: .xml, to: .edn, tools: Self.tools)
        #expect(edn.contains(":r") && edn.contains(":a"))
    }

    @Test(.enabled(if: RealToolTests.enabled && tools.formatters.deno != nil))
    func realReindentKeepsTheSelectionsEnding() async throws {
        let result = try await TextConversion.reindent(#"{"a":[1,2]}"#, fileExtension: "json", tools: Self.tools)
        #expect(result == "{ \"a\": [1, 2] }")
        #expect(try await TextConversion.reindent("{ \"a\": [1, 2] }\n", fileExtension: "json", tools: Self.tools) == nil)
    }

    @Test(.enabled(if: RealToolTests.enabled && tools.pandoc != nil))
    func realHTMLBecomesMarkdown() async throws {
        let rich = RichText(kind: .html, data: Data("<h2>Title</h2><p>Some <b>bold</b> and a <a href=\"https://example.com\">link</a>.</p>".utf8))
        let markdown = try await TextConversion.toMarkdown(rich, tools: Self.tools)
        #expect(markdown.contains("## Title"))
        #expect(markdown.contains("**bold**"))
        #expect(markdown.contains("[link](https://example.com)"))
    }
}
