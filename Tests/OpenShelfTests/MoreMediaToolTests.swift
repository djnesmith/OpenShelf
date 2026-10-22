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
}
