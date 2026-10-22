@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import OpenShelf

/// Video edits keep the container and the codecs (see `KeepFormat`).
struct KeepVideoFormatTests {
    static let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    static let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    static var hasFFmpeg: Bool { FileManager.default.isExecutableFile(atPath: ffmpeg.path) }
    let tools = ExternalTools(ffmpeg: Self.ffmpeg, cwebp: nil, ffprobe: Self.ffprobe)

    @Test func encodingKeepsTheCodec() {
        func video(_ codec: String, pixelFormat: String = "yuv420p", profile: String? = nil) -> ProbedMedia.Video {
            ProbedMedia.Video(width: 320, height: 240, codec: codec, pixelFormat: pixelFormat, profile: profile)
        }
        #expect(FFmpegEdits.videoEncoding(for: video("hevc", pixelFormat: "yuv420p10le")).contains("libx265"))
        #expect(FFmpegEdits.videoEncoding(for: video("hevc", pixelFormat: "yuv420p10le")).contains("yuv420p10le"))
        #expect(FFmpegEdits.videoEncoding(for: video("prores", pixelFormat: "yuv422p10le", profile: "HQ"), container: "mov")
            == ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"])
        #expect(FFmpegEdits.videoEncoding(for: video("prores", profile: "4444"), container: "mov").contains("yuva444p10le"))
        // ProRes can't go in an MP4, and VP9 doesn't play in one on a Mac: H.264.
        #expect(FFmpegEdits.videoEncoding(for: video("prores"), container: "mp4").contains("libx264"))
        #expect(FFmpegEdits.videoEncoding(for: video("vp9")).contains("libx264"))
        #expect(FFmpegEdits.videoEncoding(for: video("h264", pixelFormat: "yuv422p")).contains("yuv422p"))
        #expect(FFmpegEdits.videoEncoding(for: nil).contains("libx264"))
        #expect(FFmpegEdits.audioCopyOrAAC([ProbedMedia.Audio(codec: "pcm_s16le", channels: 2)], container: "mov") == ["-c:a:0", "copy"])
        #expect(FFmpegEdits.audioCopyOrAAC([ProbedMedia.Audio(codec: "pcm_s16le", channels: 2)], container: "mp4").contains("aac"))
        #expect(KeepFormat.presets(forVideoCodec: kCMVideoCodecType_HEVC).first == AVAssetExportPresetHEVCHighestQuality)
        #expect(KeepFormat.presets(forVideoCodec: kCMVideoCodecType_AppleProRes422HQ).first == AVAssetExportPresetAppleProRes422LPCM)
        #expect(KeepFormat.presets(forVideoCodec: kCMVideoCodecType_H264) == [AVAssetExportPresetHighestQuality])
    }

    /// H.264 + AAC in MP4, HEVC + PCM in MOV, ProRes 422 HQ + PCM in MOV, HEVC + AAC in MP4.
    func sources() throws -> [String: URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-keepvideo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = ["-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=25", "-f", "lavfi", "-i", "sine=frequency=440:duration=2:sample_rate=48000"]
        let recipes: [(String, [String])] = [
            ("h264.mp4", ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2"]),
            ("hevc.mov", ["-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-x265-params", "log-level=error", "-c:a", "pcm_s16le", "-ac", "2"]),
            ("prores.mov", ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le", "-ac", "2"]),
            ("hevc.mp4", ["-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-x265-params", "log-level=error", "-c:a", "aac", "-ac", "2"]),
        ]
        var urls: [String: URL] = [:]
        for (name, codecs) in recipes {
            let url = folder.appendingPathComponent(name)
            let process = Process()
            process.executableURL = Self.ffmpeg
            process.arguments = ["-y", "-loglevel", "error"] + input + codecs + [url.path]
            try process.run()
            process.waitUntilExit()
            urls[name] = url
        }
        return urls
    }

    func probe(_ url: URL) async throws -> ProbedMedia {
        try await ProbedMedia.load(url, ffprobe: Self.ffprobe)
    }

    @Test(.enabled(if: hasFFmpeg)) func everyEditKeepsContainerAndCodecs() async throws {
        let files = try sources()
        let tools = tools
        typealias Edit = (name: String, run: @Sendable (URL) async throws -> URL, keepsSound: Bool)
        let edits: [Edit] = [
            ("grayscale", { try await MediaTools.grayscale($0, tools: tools) { _ in } }, false),
            ("grayscale (ffmpeg)", { try await MediaTools.grayscaleWithFFmpeg($0, ffmpeg: Self.ffmpeg, tools: tools) { _ in } }, true),
            ("crop", { try await MediaTools.crop($0, to: CGRect(x: 0, y: 0, width: 160, height: 120), tools: tools) { _ in } }, false),
            ("crop (ffmpeg)", { try await MediaTools.cropWithFFmpeg($0, to: CGRect(x: 0, y: 0, width: 160, height: 120), ffmpeg: Self.ffmpeg, tools: tools) { _ in } }, true),
            ("flip", { try await MediaTools.rotate($0, by: .flipVertical, tools: tools) { _ in } }, false),
            ("turn", { try await MediaTools.rotate($0, by: .right, tools: tools) { _ in } }, true),
            ("trim", { try await MediaTools.trim($0, range: CMTimeRange(start: .zero, duration: MediaTime.cmTime(1)), tools: tools) { _ in } }, true),
            ("speed", { try await MediaTools.changeSpeed($0, rate: 2, keepsPitch: true, tools: tools) { _ in } }, false),
            ("speed (ffmpeg)", { try await MediaTools.changeSpeedWithFFmpeg($0, rate: 2, keepsPitch: true, ffmpeg: Self.ffmpeg, tools: tools) { _ in } }, true),
            ("reverse", { try await MediaTools.reverse($0, tools: tools) { _ in } }, true),
            ("frame rate", { try await MediaTools.changeFrameRate($0, to: 30, tools: tools) { _ in } }, true),
            ("volume", { try await MediaTools.changeVolume($0, by: 3, tools: tools) { _ in } }, true),
            ("loudness", { try await MediaTools.normalizeLoudness($0, tools: tools) { _ in } }, true),
            ("metadata", { try await MediaTools.stripMetadata($0, tools: tools) { _ in } }, true),
        ]
        for (fileName, source) in files.sorted(by: { $0.key < $1.key }) {
            let original = try await probe(source)
            for edit in edits {
                let output = try await edit.run(source)
                let label = "\(edit.name) on \(fileName)"
                #expect(output.pathExtension == source.pathExtension, "\(label): \(output.lastPathComponent)")
                let edited = try await probe(output)
                #expect(edited.video?.codec == original.video?.codec, "\(label): \(edited.video?.codec ?? "none")")
                if fileName.hasPrefix("prores") {
                    #expect(edited.video?.profile == original.video?.profile, "\(label): \(edited.video?.profile ?? "none")")
                }
                if edit.keepsSound {
                    #expect(edited.audio.first?.codec == original.audio.first?.codec, "\(label): \(edited.audio.first?.codec ?? "none")")
                }
                try? FileManager.default.removeItem(at: output)
            }
        }
    }

    // MARK: MKV, WebM and AVI, through ffmpeg

    /// H.264 + AAC in MKV, VP9 + Opus in WebM, MPEG-4 + MP3 in AVI.
    func ffmpegSources() throws -> [String: URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-keepffmpeg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = ["-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=25", "-f", "lavfi", "-i", "sine=frequency=440:duration=2:sample_rate=48000"]
        let recipes: [(String, [String])] = [
            ("clip.mkv", ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2"]),
            ("clip.webm", ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8", "-b:v", "500k", "-c:a", "libopus", "-ac", "2"]),
            ("clip.avi", ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-ac", "2"]),
        ]
        var urls: [String: URL] = [:]
        for (name, codecs) in recipes {
            let url = folder.appendingPathComponent(name)
            let process = Process()
            process.executableURL = Self.ffmpeg
            process.arguments = ["-y", "-loglevel", "error"] + input + codecs + [url.path]
            try process.run()
            process.waitUntilExit()
            urls[name] = url
        }
        return urls
    }

    @Test(.enabled(if: hasFFmpeg)) func ffmpegContainersKeepTheirFormat() async throws {
        let files = try ffmpegSources()
        let tools = tools
        typealias Edit = (name: String, run: @Sendable (URL) async throws -> URL)
        let edits: [Edit] = [
            ("grayscale", { try await MediaTools.grayscale($0, tools: tools) { _ in } }),
            ("crop", { try await MediaTools.crop($0, to: CGRect(x: 0, y: 0, width: 160, height: 120), tools: tools) { _ in } }),
            ("flip", { try await MediaTools.rotate($0, by: .flipHorizontal, tools: tools) { _ in } }),
            ("turn", { try await MediaTools.rotate($0, by: .right, tools: tools) { _ in } }),
            ("trim", { try await MediaTools.trim($0, range: CMTimeRange(start: .zero, duration: MediaTime.cmTime(1)), tools: tools) { _ in } }),
            ("speed", { try await MediaTools.changeSpeed($0, rate: 2, keepsPitch: true, tools: tools) { _ in } }),
            ("reverse", { try await MediaTools.reverse($0, tools: tools) { _ in } }),
            ("frame rate", { try await MediaTools.changeFrameRate($0, to: 30, tools: tools) { _ in } }),
            ("volume", { try await MediaTools.changeVolume($0, by: 3, tools: tools) { _ in } }),
            ("loudness", { try await MediaTools.normalizeLoudness($0, tools: tools) { _ in } }),
            ("metadata", { try await MediaTools.stripMetadata($0, tools: tools) { _ in } }),
            ("mute", { try await MediaTools.mute($0, tools: tools) { _ in } }),
        ]
        for (fileName, source) in files.sorted(by: { $0.key < $1.key }) {
            let original = try await probe(source)
            for edit in edits {
                let label = "\(edit.name) on \(fileName)"
                let output: URL
                do { output = try await edit.run(source) } catch {
                    Issue.record("\(label) failed: \(error.localizedDescription)")
                    continue
                }
                #expect(output.pathExtension == source.pathExtension, "\(label): \(output.lastPathComponent)")
                let edited = try await probe(output)
                #expect(edited.video?.codec == original.video?.codec, "\(label): \(edited.video?.codec ?? "none")")
                if edit.name == "mute" {
                    #expect(edited.audio.isEmpty, "\(label)")
                } else {
                    #expect(edited.audio.first?.codec == original.audio.first?.codec, "\(label): \(edited.audio.first?.codec ?? "none")")
                }
                if edit.name == "turn" {
                    #expect(edited.video?.displaySize == CGSize(width: 240, height: 320), "\(label): \(String(describing: edited.video?.displaySize))")
                }
                try? FileManager.default.removeItem(at: output)
            }
            let frame = try await MediaTools.stillFrame(source, at: 1, tools: tools)
            #expect(frame.pathExtension == "png", "still frame on \(fileName)")
        }
    }

    /// The editors' loading, which shows frames ffmpeg decodes for files AVFoundation can't open.
    @MainActor
    @Test(.enabled(if: hasFFmpeg)) func editorsOpenFFmpegContainers() async throws {
        for (name, url) in try ffmpegSources().sorted(by: { $0.key < $1.key }) {
            let trim = TrimModel(url: url)
            await trim.load()
            #expect(trim.loadError == nil && trim.duration > 1.5, "trim \(name): \(trim.loadError ?? "")")
            let crop = VideoCropModel(url: url)
            await crop.load()
            #expect(crop.frame != nil && crop.loadError == nil, "crop \(name)")
            let rotate = RotateModel(url: url)
            await rotate.load()
            #expect(rotate.frame != nil && rotate.loadError == nil, "rotate \(name)")
            let still = StillFrameModel(url: url)
            await still.load()
            await still.updatePreview()
            #expect(still.preview != nil && still.loadError == nil, "still \(name)")
        }
    }
}
