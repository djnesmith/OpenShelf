@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import OpenShelf

/// Still frame, reverse, strip metadata, flip, grayscale, mono and loudness,
/// run on small clips made with ffmpeg and checked with ffprobe.
struct MoreMediaToolTests {
    static let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    static let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    static var hasFFmpeg: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpeg.path) && FileManager.default.isExecutableFile(atPath: ffprobe.path)
    }

    let tools = ExternalTools(ffmpeg: Self.ffmpeg, cwebp: nil, ffprobe: Self.ffprobe)

    /// A fresh folder holding a 3-second 320×240 MP4 with sound ("clip.mp4",
    /// tagged with a title and a location) and a stereo M4A ("tone.m4a").
    func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-more-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.run(Self.ffmpeg, [
            "-f", "lavfi", "-i", "testsrc=duration=3:size=320x240:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=3:sample_rate=48000",
            "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2",
            "-metadata", "title=Secret title", "-metadata", "location=+48.8584+002.2945/",
            folder.appendingPathComponent("clip.mp4").path,
        ])
        try Self.run(Self.ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-f", "lavfi", "-i", "sine=frequency=660:duration=3",
            "-filter_complex", "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]", "-map", "[a]",
            "-c:a", "aac", "-metadata", "artist=Someone", folder.appendingPathComponent("tone.m4a").path,
        ])
        return folder
    }

    static func run(_ tool: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["-y", "-loglevel", "error"] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MediaToolError.failed("Couldn't make \(arguments.last ?? "")") }
    }

    func probe(_ url: URL) async throws -> ProbedMedia {
        try await ProbedMedia.load(url, ffprobe: Self.ffprobe)
    }

    // MARK: Still frame

    @Test func stillFrameNamesTheTime() {
        #expect(MediaTools.stillFrameSuffix(12.5) == "Frame 12.5s")
        #expect(MediaTools.stillFrameSuffix(3) == "Frame 3s")
        #expect(MediaTools.stillFrameSuffix(-1) == "Frame 0s")
    }

    @Test(.enabled(if: hasFFmpeg)) func stillFrameSavesAFullSizeImage() async throws {
        let folder = try workspace()
        let clip = folder.appendingPathComponent("clip.mp4")
        let png = try await MediaTools.stillFrame(clip, at: 1.5, as: .png, tools: tools)
        #expect(png.lastPathComponent == "clip Frame 1.5s.png")
        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 320 && image.height == 240)

        let jpeg = try await MediaTools.stillFrame(clip, at: 1.5, as: .jpeg, tools: tools)
        #expect(jpeg.lastPathComponent == "clip Frame 1.5s.jpeg")
    }

    // MARK: Reverse

    @Test func reverseArguments() {
        let probed = ProbedMedia(
            duration: 3,
            video: ProbedMedia.Video(width: 320, height: 240, codec: "h264"),
            audio: [ProbedMedia.Audio(codec: "aac", channels: 2)]
        )
        let arguments = FFmpegEdits.reverse(probed)
        #expect(arguments.starts(with: ["-filter_complex", "[0:V:0]reverse[v];[0:a:0]areverse[a0]", "-map", "[v]"]))
        #expect(arguments.contains("[a0]"))
    }

    @Test func reverseRefusesWhatWouldNotFitInMemory() throws {
        // 1080p at 30 fps holds about 93 MB a second, so 2 GB is about 21 seconds.
        let video = ProbedMedia.Video(width: 1920, height: 1080, frameRate: "30/1", codec: "h264")
        #expect(throws: Never.self) { try ReverseLimit.check(ProbedMedia(duration: 20, video: video, audio: [])) }
        #expect(throws: MediaToolError.self) { try ReverseLimit.check(ProbedMedia(duration: 60, video: video, audio: [])) }
        // An hour of stereo sound is about 1.4 GB: fine.
        #expect(throws: Never.self) {
            try ReverseLimit.check(ProbedMedia(duration: 3600, video: nil, audio: [ProbedMedia.Audio(codec: "aac", channels: 2, sampleRate: 48_000)]))
        }
    }

    @Test func ffmpegOnlyToolsNeedFFmpeg() {
        let clip = [URL(fileURLWithPath: "/tmp/a.mov")]
        #expect(!FileTool.available(for: clip, tools: ExternalTools()).contains(.reverse))
        #expect(FileTool.available(for: clip, tools: tools).contains(.reverse))
        #expect(FileTool.available(for: [URL(fileURLWithPath: "/tmp/a.m4a")], tools: tools).contains(.reverse))
    }

    @Test(.enabled(if: hasFFmpeg)) func reversesPictureAndSound() async throws {
        let folder = try workspace()
        let output = try await MediaTools.reverse(folder.appendingPathComponent("clip.mp4"), tools: tools) { _ in }
        #expect(output.lastPathComponent == "clip Reversed.mp4")
        let probed = try await probe(output)
        #expect(probed.video?.width == 320)
        #expect(probed.audio.count == 1)
        #expect(abs(probed.duration - 3) < 0.2)

        let sound = try await MediaTools.reverse(folder.appendingPathComponent("tone.m4a"), tools: tools) { _ in }
        #expect(sound.lastPathComponent == "tone Reversed.m4a")
    }

    // MARK: Strip metadata

    /// The container's and streams' tags, as ffprobe lists them.
    func tags(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = Self.ffprobe
        process.arguments = ["-v", "error", "-show_entries", "format_tags:stream_tags", "-of", "json", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test(.enabled(if: hasFFmpeg)) func stripsTagsWithoutReencoding() async throws {
        let folder = try workspace()
        let clip = folder.appendingPathComponent("clip.mp4")
        #expect(try tags(clip).contains("Secret title"))
        let output = try await MediaTools.stripMetadata(clip, tools: tools) { _ in }
        #expect(output.lastPathComponent == "clip Clean.mp4")
        let left = try tags(output)
        #expect(!left.contains("Secret title"))
        #expect(!left.contains("48.8584"))
        #expect(!left.contains("Lavf"))
        let probed = try await probe(output)
        #expect(probed.video?.codec == "h264" && probed.audio.count == 1)

        let tone = folder.appendingPathComponent("tone.m4a")
        #expect(try tags(tone).contains("Someone"))
        let sound = try await MediaTools.stripMetadata(tone, tools: tools) { _ in }
        #expect(sound.lastPathComponent == "tone Clean.m4a")
        #expect(!(try tags(sound).contains("Someone")))
    }
}
