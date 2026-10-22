import Foundation
import Testing
@testable import OpenShelf

struct CommandLineToolTests {
    /// Every executable `ExternalTools.detect` looks for. A tool added to
    /// detection but not here leaves its field empty, and the test below fails.
    static let commandNames = [
        "ffmpeg", "ffprobe", "cwebp", "ebook-convert", "pandoc", "yq", "cjxl", "duckdb", "jet",
        "deno", "cljfmt", "ruff", "shfmt", "swift-format", "pg_format", "clang-format", "gofmt", "rustfmt",
    ]

    /// Detects in a folder holding a stand-in for every tool.
    func everythingInstalled() throws -> ExternalTools {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-tools-\(UUID().uuidString)", isDirectory: true)
        let bin = folder.appendingPathComponent("bin", isDirectory: true)
        let soffice = folder.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: soffice.deletingLastPathComponent(), withIntermediateDirectories: true)
        for stub in Self.commandNames.map(bin.appendingPathComponent) + [soffice] {
            FileManager.default.createFile(atPath: stub.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        let locations = ToolLocations(commandDirectories: [bin], libreOfficeApps: [soffice.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()])
        return ExternalTools.detect(in: locations, ignoring: [])
    }

    /// Every tool the code resolves has a row in Settings → Extra Formats:
    /// ffmpeg and LibreOffice above, the rest as command-line tools. ffprobe
    /// comes with ffmpeg.
    @Test func everyDetectedToolIsListedInSettings() throws {
        let tools = try everythingInstalled()
        let listed = Set(ExtraTool.allCases.compactMap { $0.path(in: tools) } + CommandLineTool.allCases.compactMap { $0.path(in: tools) })
        let fields = Array(Mirror(reflecting: tools).children) + Array(Mirror(reflecting: tools.formatters).children)
        var checked = 0
        for field in fields {
            guard let label = field.label, label != "formatters" else { continue }
            let path = try #require(field.value as? URL?, "\(label) isn't a tool path")
            let found = try #require(path, "\(label) wasn't detected; add its command to commandNames")
            if label == "ffprobe" { continue }
            #expect(listed.contains(found), "\(label) has no row in Settings → Extra Formats")
            checked += 1
        }
        #expect(checked == ExtraTool.allCases.count + CommandLineTool.allCases.count)
    }

    @Test func collapsedRowCountsWhatsInstalled() throws {
        #expect(CommandLineTool.title(tools: ExternalTools()) == "Command-Line Tools · 0 of 16 installed")
        #expect(CommandLineTool.title(tools: try everythingInstalled()) == "Command-Line Tools · 16 of 16 installed")
    }

    @Test func eachRowHasANameAndAHomebrewCommand() {
        #expect(Set(CommandLineTool.allCases.map(\.name)).count == CommandLineTool.allCases.count)
        for tool in CommandLineTool.allCases {
            #expect(tool.homebrewCommand.hasPrefix("brew install "), "\(tool)")
            #expect(!tool.adds.isEmpty, "\(tool)")
        }
        #expect(CommandLineTool.pgFormat.homebrewCommand == "brew install pgformatter")
        #expect(CommandLineTool.jet.homebrewCommand == "brew install borkdude/brew/jet")
    }
}
