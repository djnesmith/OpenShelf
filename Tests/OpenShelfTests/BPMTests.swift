import Foundation
import Testing
@testable import OpenShelf

/// The BPM tool through a fake aubio, plus one run of the real one when it's installed.
struct BPMTests {
    static let aubio = URL(fileURLWithPath: "/opt/homebrew/bin/aubio")
    static let tools = ExternalTools(ffmpeg: nil, cwebp: nil, aubio: aubio)

    /// Answers like `aubio tempo` did on real files: tempo per file name, or
    /// the error it printed for an unreadable one.
    static let fake = FakeToolRunner { invocation in
        let file = invocation.arguments.last ?? ""
        switch URL(fileURLWithPath: file).lastPathComponent {
        case "drums.mp3": return ["146.44 bpm"]
        case "short.m4a": return ["98.5 bpm (uncertain)"]
        case "Funk.aiff": return ["unknown bpm"]
        case "empty.wav":
            let last = "RuntimeError: AUBIO ERROR: source_wavread: Failed opening \(file) (could not find RIFF header)"
            throw ProcessFailure(tool: "aubio", message: last, errorOutput: "Traceback (most recent call last):\n  File \"/opt/homebrew/bin/aubio\", line 7\n\(last)\n")
        case "renamed.mp3":
            // An AIFF saved as .mp3: Python's traceback ends on a vaguer line.
            throw ProcessFailure(
                tool: "aubio",
                message: "SystemError: <class 'aubio.source'> returned a result with an exception set",
                errorOutput: """
                RuntimeError: AUBIO ERROR: source_apple_audio: Failed opening \(file), error in ExtAudioFileOpenURL ('dta?')

                The above exception was the direct cause of the following exception:

                Traceback (most recent call last):
                SystemError: <class 'aubio.source'> returned a result with an exception set
                """
            )
        case "broken.wav":
            throw ProcessFailure(tool: "aubio", message: "")
        default: return []
        }
    }

    func detect(_ names: [String]) async throws -> [BPM.Result] {
        try await BPM.detect(names.map { URL(fileURLWithPath: "/Users/me/Music/\($0)") }, tools: Self.tools, runner: Self.fake.runner)
    }

    @Test func parsesWhatAubioPrints() {
        #expect(BPM.parse("146.44 bpm") == .bpm(146, uncertain: false))
        #expect(BPM.parse("147.63 bpm") == .bpm(148, uncertain: false))
        #expect(BPM.parse("98.50 bpm (uncertain)") == .bpm(99, uncertain: true))
        #expect(BPM.parse("unknown bpm") == .noBeat)
        #expect(BPM.parse("Traceback (most recent call last):") == nil)
        #expect(BPM.parse("nan bpm") == nil)
    }

    @Test func runsAubioTempoOnTheFile() async throws {
        let fake = FakeToolRunner { _ in ["146.44 bpm"] }
        let file = URL(fileURLWithPath: "/Users/me/-My Song ü.mp3")
        let result = try await BPM.detect(file, tools: Self.tools, runner: fake.runner)
        #expect(result == BPM.Result(file: file, outcome: .bpm(146, uncertain: false)))
        #expect(fake.invocations == [ToolInvocation(executable: Self.aubio, arguments: ["tempo", file.path])])
    }

    @Test func severalFilesGetOneLineEachInOrder() async throws {
        let results = try await detect(["drums.mp3", "Funk.aiff", "empty.wav", "short.m4a"])
        #expect(BPM.report(results) == """
        drums.mp3 — 146 BPM
        Funk.aiff — no steady beat found
        empty.wav — couldn’t read: source_wavread: Failed opening empty.wav (could not find RIFF header)
        short.m4a — 99 BPM (uncertain, few beats)
        """)
    }

    @Test func aFailingFileDoesNotStopTheOthers() async throws {
        let results = try await detect(["empty.wav", "drums.mp3"])
        #expect(results.map(\.outcome) == [
            .failed("source_wavread: Failed opening empty.wav (could not find RIFF header)"),
            .bpm(146, uncertain: false),
        ])
    }

    @Test func aubioErrorLineIsShownOverPythonsLastLine() async throws {
        let results = try await detect(["renamed.mp3", "broken.wav"])
        #expect(results.map(\.outcome) == [
            .failed("source_apple_audio: Failed opening renamed.mp3, error in ExtAudioFileOpenURL ('dta?')"),
            .failed("aubio failed"),
        ])
    }

    /// aubio read the file but printed nothing usable ("inf bpm", or no line).
    @Test func noTempoLineMeansNoSteadyBeat() async throws {
        let results = try await detect(["silent.wav"])
        #expect(results.map(\.outcome) == [.noBeat])
        #expect(BPM.parse("inf bpm") == nil)
    }

    @Test func missingAubioFailsWithoutRunningAnything() async throws {
        let fake = FakeToolRunner()
        await #expect(throws: MissingToolError(name: "aubio")) {
            _ = try await BPM.detect([URL(fileURLWithPath: "/tmp/a.mp3")], tools: ExternalTools(ffmpeg: nil, cwebp: nil), runner: fake.runner)
        }
        #expect(fake.invocations.isEmpty)
    }

    /// Homebrew's aubio can't read FLAC or OGG, so those files don't get the wedge.
    @Test func wedgeShowsOnlyWithAubioAndForFilesItReads() {
        func offered(_ names: [String], _ tools: ExternalTools) -> Bool {
            FileTool.available(for: names.map { URL(fileURLWithPath: "/tmp/\($0)") }, tools: tools).contains(.bpm)
        }
        let readable = ["a.wav", "b.mp3", "c.m4a", "d.aif", "e.aiff", "f.caf", "g.aac", "h.opus"]
        #expect(offered(readable, Self.tools))
        #expect(offered(["A.MP3", "B.Wav"], Self.tools))
        #expect(!offered(readable, ExternalTools(ffmpeg: nil, cwebp: nil)))
        #expect(!offered(["a.flac"], Self.tools))
        #expect(!offered(["a.ogg"], Self.tools))
        #expect(!offered(["a.mp3", "b.flac"], Self.tools))
        #expect(!offered(["a.mp4"], Self.tools))
    }

    @Test(.enabled(if: ExternalTools.detect().aubio != nil)) func realAubioHearsNoBeatInASystemSound() async throws {
        let sound = URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")
        let result = try await BPM.detect(sound, tools: ExternalTools.detect())
        #expect(result.outcome == .noBeat)
    }
}
