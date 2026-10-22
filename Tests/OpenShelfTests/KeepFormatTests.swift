@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import OpenShelf

/// Edits save audio in the format they were given (see `KeepFormat`).
struct KeepFormatTests {
    static let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    static let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    static var hasFFmpeg: Bool { FileManager.default.isExecutableFile(atPath: ffmpeg.path) }
    let tools = ExternalTools(ffmpeg: Self.ffmpeg, cwebp: nil, ffprobe: Self.ffprobe)
    static let encoders: Set<String> = ["libmp3lame", "aac", "alac", "flac", "pcm_s16le", "pcm_s24le", "pcm_s16be", "libopus", "vorbis", "wmav2"]

    func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test func mp3KeepsItsBitrateOrVBR() {
        let constant = KeepFormat.audio(for: url("a.mp3"), track: ProbedMedia.Audio(codec: "mp3", channels: 2, sampleRate: 44_100, bitRate: 192_000), encoders: Self.encoders)
        #expect(constant.pathExtension == "mp3" && constant.arguments(index: 0) == ["-c:a:0", "libmp3lame", "-b:a:0", "192000", "-ar:a:0", "44100"])
        let variable = KeepFormat.audio(for: url("a.mp3"), track: ProbedMedia.Audio(codec: "mp3", channels: 2, bitRate: 187_400), encoders: Self.encoders)
        #expect(variable.arguments(index: 1) == ["-c:a:1", "libmp3lame", "-q:a:1", "2"])
    }

    @Test func eachFamilyKeepsItsCodec() {
        let cases: [(String, String, String)] = [
            ("a.m4a", "aac", "aac"), ("a.m4a", "alac", "alac"), ("a.wav", "pcm_s24le", "pcm_s24le"), ("a.aiff", "pcm_s16be", "pcm_s16be"),
            ("a.flac", "flac", "flac"), ("a.ogg", "opus", "libopus"), ("a.ogg", "vorbis", "vorbis"), ("a.opus", "opus", "libopus"),
            ("a.wma", "wmav2", "wmav2"), ("a.caf", "alac", "alac"),
        ]
        for (name, codec, encoder) in cases {
            let plan = KeepFormat.audio(for: url(name), track: ProbedMedia.Audio(codec: codec, channels: 2), encoders: Self.encoders)
            #expect(plan.pathExtension == url(name).pathExtension && plan.encoder == encoder, "\(name) \(codec)")
        }
    }

    @Test func fallsBackToM4AAndSaysWhy() {
        #expect(KeepFormat.audio(for: url("a.ac3"), track: ProbedMedia.Audio(codec: "ac3", channels: 2), encoders: Self.encoders).pathExtension == "m4a")
        #expect(KeepFormat.audio(for: url("a.mp3"), track: nil, encoders: ["aac"]).pathExtension == "m4a")
        #expect(KeepFormat.note(source: url("a.mp3"), output: url("a Reversed.m4a"), tools: ExternalTools()) == "Saved as M4A: keeping MP3 needs ffmpeg.")
        #expect(KeepFormat.note(source: url("a.ac3"), output: url("a Reversed.m4a"), tools: tools) == "Saved as M4A: OpenShelf can’t write AC3 here.")
        #expect(KeepFormat.note(source: url("a.mp3"), output: url("a Reversed.mp3"), tools: tools) == nil)
    }

    /// One file of each family, made with ffmpeg.
    func workspace() throws -> (folder: URL, files: [String: URL]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-keep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tone = ["-f", "lavfi", "-i", "sine=frequency=440:duration=2:sample_rate=44100", "-ac", "2"]
        let recipes: [(String, [String])] = [
            ("cbr.mp3", ["-c:a", "libmp3lame", "-b:a", "192k"]), ("vbr.mp3", ["-c:a", "libmp3lame", "-q:a", "2"]),
            ("aac.m4a", ["-c:a", "aac"]), ("deep.wav", ["-c:a", "pcm_s24le"]), ("tone.aiff", ["-c:a", "pcm_s16be"]),
            ("tone.flac", ["-c:a", "flac"]), ("vorbis.ogg", ["-c:a", "vorbis", "-strict", "experimental"]),
            ("tone.opus", ["-c:a", "libopus", "-b:a", "96k"]), ("tone.wma", ["-c:a", "wmav2", "-b:a", "128k"]),
        ]
        var files: [String: URL] = [:]
        for (name, codec) in recipes {
            let url = folder.appendingPathComponent(name)
            let process = Process()
            process.executableURL = Self.ffmpeg
            process.arguments = ["-y", "-loglevel", "error"] + tone + codec + [url.path]
            try process.run()
            process.waitUntilExit()
            files[name] = url
        }
        return (folder, files)
    }

    func audio(_ url: URL) async throws -> ProbedMedia.Audio {
        try #require(try await ProbedMedia.load(url, ffprobe: Self.ffprobe).audio.first)
    }

    @Test(.enabled(if: hasFFmpeg)) func reversedAudioKeepsItsFormat() async throws {
        let (_, files) = try workspace()
        let expected: [String: String] = [
            "cbr.mp3": "mp3", "vbr.mp3": "mp3", "aac.m4a": "aac", "deep.wav": "pcm_s24le", "tone.aiff": "pcm_s16be",
            "tone.flac": "flac", "vorbis.ogg": "vorbis", "tone.opus": "opus", "tone.wma": "wmav2",
        ]
        for (name, codec) in expected.sorted(by: { $0.key < $1.key }) {
            let source = try #require(files[name])
            let output = try await MediaTools.reverse(source, tools: tools) { _ in }
            #expect(output.pathExtension == source.pathExtension, "\(name) → \(output.lastPathComponent)")
            let written = try await audio(output)
            #expect(written.codec == codec, "\(name): \(written.codec)")
            #expect(written.sampleRate == 44_100 || codec == "opus", "\(name): \(written.sampleRate ?? 0)")
        }
        // The MP3 at its own bitrate.
        let cbr = try await MediaTools.reverse(try #require(files["cbr.mp3"]), tools: tools) { _ in }
        #expect(abs((try await audio(cbr).bitRate ?? 0) - 192_000) < 8_000)
    }

    @Test(.enabled(if: hasFFmpeg)) func otherAudioEditsKeepMP3() async throws {
        let (_, files) = try workspace()
        let mp3 = try #require(files["cbr.mp3"])
        let outputs: [URL] = [
            try await MediaTools.trim(mp3, range: CMTimeRange(start: .zero, duration: MediaTime.cmTime(1)), tools: tools) { _ in },
            try await MediaTools.changeSpeed(mp3, rate: 2, keepsPitch: true, tools: tools) { _ in },
            try await MediaTools.changeVolume(mp3, by: -6, tools: tools) { _ in },
            try await MediaTools.mono(mp3, tools: tools) { _ in },
            try await MediaTools.normalizeLoudness(mp3, tools: tools) { _ in },
        ]
        for output in outputs {
            #expect(output.pathExtension == "mp3", "\(output.lastPathComponent)")
            #expect(try await audio(output).codec == "mp3", "\(output.lastPathComponent)")
        }
        // Without ffmpeg, Trim falls back to what AVFoundation writes, and says why.
        let trimmed = try await MediaTools.trim(mp3, range: CMTimeRange(start: .zero, duration: MediaTime.cmTime(1)), tools: ExternalTools()) { _ in }
        #expect(trimmed.pathExtension == "m4a")
        #expect(KeepFormat.note(source: mp3, output: trimmed, tools: ExternalTools())?.contains("needs ffmpeg") == true)
    }
}
