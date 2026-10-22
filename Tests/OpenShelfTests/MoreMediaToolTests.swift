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
        #expect(FileTool.available(for: clip, tools: tools).contains(.volume))
        #expect(!FileTool.available(for: clip, tools: ExternalTools()).contains(.volume))
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

    // MARK: Mono

    @Test func filteredSoundKeepsLosslessContainers() {
        #expect(FFmpegEdits.filteredAudioContainer(for: URL(fileURLWithPath: "/tmp/a.WAV")) == "wav")
        #expect(FFmpegEdits.filteredAudioContainer(for: URL(fileURLWithPath: "/tmp/a.flac")) == "flac")
        #expect(FFmpegEdits.filteredAudioContainer(for: URL(fileURLWithPath: "/tmp/a.mp3")) == "m4a")
        let track = ProbedMedia.Audio(codec: "pcm_s16le", channels: 1)
        #expect(FFmpegEdits.filteredAudio("wav", track: track, index: 0) == ["-c:a:0", "pcm_s16le"])
        #expect(FFmpegEdits.filteredAudio("m4a", track: track, index: 0).contains("aac"))
    }

    @Test(.enabled(if: hasFFmpeg)) func mixesDownToOneChannel() async throws {
        let folder = try workspace()
        let tone = folder.appendingPathComponent("tone.m4a")
        #expect(try await probe(tone).audio.first?.channels == 2)
        let output = try await MediaTools.mono(tone, tools: tools) { _ in }
        #expect(output.lastPathComponent == "tone Mono.m4a")
        #expect(try await probe(output).audio.first?.channels == 1)
    }

    // MARK: Loudness

    /// Integrated loudness in LUFS, as ffmpeg's EBU R128 meter reports it.
    func loudness(_ url: URL) throws -> Double {
        let process = Process()
        process.executableURL = Self.ffmpeg
        process.arguments = ["-nostats", "-i", url.path, "-map", "0:a:0", "-af", "ebur128", "-f", "null", "-"]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // The summary's "I:  -16.0 LUFS" line comes last.
        let line = try #require(text.components(separatedBy: "\n").last { $0.contains("I:") && $0.contains("LUFS") })
        let number = line.components(separatedBy: "I:")[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]
        return try #require(Double(number))
    }

    @Test func loudnessKeepsThePictureAndSampleRate() {
        let probed = ProbedMedia(
            duration: 3,
            video: ProbedMedia.Video(width: 320, height: 240, codec: "h264"),
            audio: [ProbedMedia.Audio(codec: "aac", channels: 2, sampleRate: 44_100)]
        )
        let arguments = FFmpegEdits.normalizeLoudness(probed, container: "mp4")
        #expect(arguments.contains("[0:a:0]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100[a0]"))
        #expect(arguments.starts(with: ["-filter_complex"]) && arguments.contains("copy"))
    }

    @Test(.enabled(if: hasFFmpeg)) func bringsSoundToTheTarget() async throws {
        let folder = try workspace()
        let tone = folder.appendingPathComponent("tone.m4a")
        #expect(abs(try loudness(tone) - -16) > 2)
        let output = try await MediaTools.normalizeLoudness(tone, tools: tools) { _ in }
        #expect(output.lastPathComponent == "tone Normalized.m4a")
        #expect(abs(try loudness(output) - -16) < 1.5)
        #expect(try await probe(output).audio.first?.sampleRate == 44_100)

        let clip = try await MediaTools.normalizeLoudness(folder.appendingPathComponent("clip.mp4"), tools: tools) { _ in }
        #expect(clip.lastPathComponent == "clip Normalized.mp4")
        #expect(try await probe(clip).video?.codec == "h264")
    }

    // MARK: Flip and grayscale

    @Test func flipsVertically() {
        #expect(FFmpegEdits.rotationFilter(.flipVertical) == "vflip")
        #expect(!VideoRotation.flipVertical.isLossless && VideoRotation.flipVertical.degrees == 0)
        let size = CGSize(width: 320, height: 240)
        let rect = CGRect(origin: .zero, size: size).applying(VideoRotation.flipVertical.applied(to: .identity, naturalSize: size))
        #expect(abs(rect.minX) < 0.001 && abs(rect.minY) < 0.001 && rect.size == size)
    }

    /// The colour of the pixel at the centre of `image`, as RGB 0–255.
    func centreColour(_ image: CGImage) throws -> (Int, Int, Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let crop = try #require(image.cropping(to: CGRect(x: image.width / 4, y: image.height / 2, width: 1, height: 1)))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test(.enabled(if: hasFFmpeg)) func flipAndGrayscaleChangeThePicture() async throws {
        let folder = try workspace()
        let clip = folder.appendingPathComponent("clip.mp4")
        let flipped = try await MediaTools.rotate(clip, by: .flipVertical, tools: tools) { _ in }
        #expect(flipped.lastPathComponent == "clip Rotated.mp4")
        #expect(try await probe(flipped).video.map { ($0.width, $0.height) } ?? (0, 0) == (320, 240))

        let gray = try await MediaTools.grayscale(clip, tools: tools) { _ in }
        #expect(gray.lastPathComponent == "clip Grayscale.mp4")
        #expect(try await probe(gray).audio.count == 1)
        // testsrc's colour bars: a coloured pixel before, an equal-channel one after.
        let (r0, g0, b0) = try centreColour(try await MediaTools.frame(of: clip, at: 1, maximumSize: nil, tools: tools))
        #expect(max(abs(r0 - g0), abs(g0 - b0), abs(r0 - b0)) > 30)
        let (r, g, b) = try centreColour(try await MediaTools.frame(of: gray, at: 1, maximumSize: nil, tools: tools))
        #expect(max(abs(r - g), abs(g - b), abs(r - b)) < 8)

        let viaFFmpeg = try await MediaTools.grayscaleWithFFmpeg(clip, ffmpeg: Self.ffmpeg, tools: tools) { _ in }
        let (fr, fg, fb) = try centreColour(try await MediaTools.frame(of: viaFFmpeg, at: 1, maximumSize: nil, tools: tools))
        #expect(max(abs(fr - fg), abs(fg - fb), abs(fr - fb)) < 8)
    }

    // MARK: Volume

    /// ffmpeg volumedetect's mean and peak, in dBFS.
    func levels(_ url: URL) throws -> (mean: Double, peak: Double) {
        let process = Process()
        process.executableURL = Self.ffmpeg
        process.arguments = ["-nostats", "-i", url.path, "-map", "0:a:0", "-af", "volumedetect", "-f", "null", "-"]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        func value(_ key: String) throws -> Double {
            let line = try #require(text.components(separatedBy: "\n").first { $0.contains(key) })
            return try #require(Double(line.components(separatedBy: key)[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]))
        }
        return (try value("mean_volume:"), try value("max_volume:"))
    }

    @Test func volumeArguments() {
        let probed = ProbedMedia(
            duration: 3,
            video: ProbedMedia.Video(width: 320, height: 240, codec: "h264"),
            audio: [ProbedMedia.Audio(codec: "pcm_s16le", channels: 2)]
        )
        let arguments = FFmpegEdits.volume(probed, decibels: 6, container: "wav")
        #expect(arguments == [
            "-filter_complex", "[0:a:0]volume=6dB,alimiter=limit=0.891:level=false[a0]",
            "-map", "0:V:0", "-c:v", "copy", "-map", "[a0]", "-c:a:0", "pcm_s16le",
        ])
        #expect(FFmpegEdits.volume(probed, decibels: -20, container: "m4a")[1].hasPrefix("[0:a:0]volume=-20dB,"))
    }

    @Test(.enabled(if: hasFFmpeg)) func changesVolumeWithoutClipping() async throws {
        let folder = try workspace()
        let tone = folder.appendingPathComponent("tone.m4a")
        let before = try levels(tone)

        let louder = try await MediaTools.changeVolume(tone, by: 6, tools: tools) { _ in }
        #expect(louder.lastPathComponent == "tone Louder.m4a")
        #expect(abs(try levels(louder).mean - before.mean - 6) < 1)

        let quieter = try await MediaTools.changeVolume(tone, by: -6, tools: tools) { _ in }
        #expect(quieter.lastPathComponent == "tone Quieter.m4a")
        #expect(abs(try levels(quieter).mean - before.mean + 6) < 1)

        // +20 dB would put the peaks well above full scale; the limiter holds
        // them at -1 dBFS. Checked on WAV, which stays WAV: AAC's own encoding
        // can overshoot a heavily limited tone slightly.
        #expect(before.peak + 20 > 1)
        let wav = folder.appendingPathComponent("tone.wav")
        try Self.run(Self.ffmpeg, ["-i", tone.path, "-c:a", "pcm_s16le", wav.path])
        let loudest = try await MediaTools.changeVolume(wav, by: 20, tools: tools) { _ in }
        #expect(loudest.lastPathComponent == "tone Louder.wav")
        #expect(try levels(loudest).peak <= -0.9)

        let clip = try await MediaTools.changeVolume(folder.appendingPathComponent("clip.mp4"), by: 3, tools: tools) { _ in }
        #expect(clip.lastPathComponent == "clip Louder.mp4")
        #expect(try await probe(clip).video?.codec == "h264")
    }

    // MARK: Fit size

    @Test func plansBitratesForASize() throws {
        // 25 MB over a minute: about 3.2 Mbit/s, so 128k sound and 1080p at most.
        let video = try FitSizePlan.make(bytes: 25_000_000, duration: 60, hasVideo: true)
        #expect(video.audioBitRate == 128_000 && video.videoBitRate == 3_038_666 && video.maximumHeight == 1080)
        let audio = try FitSizePlan.make(bytes: 10_000_000, duration: 600, hasVideo: false)
        #expect(audio.videoBitRate == nil && audio.audioBitRate == 126_666)
        #expect(throws: MediaToolError.self) { try FitSizePlan.make(bytes: 1_000_000, duration: 3600, hasVideo: true) }
        let tiny = try FitSizePlan.make(bytes: 2_000_000, duration: 60, hasVideo: true)
        #expect(tiny.maximumHeight == 360 && tiny.audioBitRate == 64_000)
    }

    @Test(.enabled(if: hasFFmpeg)) func fitsUnderTheSize() async throws {
        let folder = try workspace()
        // 10 seconds of busy 720p at a generous rate: several MB.
        let big = folder.appendingPathComponent("big.mp4")
        try Self.run(Self.ffmpeg, ["-f", "lavfi", "-i", "testsrc2=duration=10:size=1280x720:rate=30", "-f", "lavfi", "-i", "sine=duration=10",
            "-c:v", "libx264", "-preset", "ultrafast", "-b:v", "8M", "-pix_fmt", "yuv420p", "-c:a", "aac", big.path])
        let target: Int64 = 1_000_000
        let output = try await MediaTools.fitSize(big, bytes: target, tools: tools) { _ in }
        #expect(output.lastPathComponent == "big 1MB.mp4")
        let size = try #require(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size <= target && size > target / 2)
        #expect(try await probe(output).video?.height == 480)
        // No two-pass logs left behind.
        let logs = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("openshelf-2pass-") }
        #expect(logs.isEmpty)

        let tone = folder.appendingPathComponent("tone.m4a")
        await #expect(throws: MediaToolError.self) { try await MediaTools.fitSize(tone, bytes: 50_000_000, tools: tools) { _ in } }
    }

    // MARK: Compress audio

    @Test func afconvertWritesAACAtTheRate() {
        let arguments = MediaTools.afconvertArguments(URL(fileURLWithPath: "/tmp/a.wav"), kilobits: 96, to: URL(fileURLWithPath: "/tmp/b.m4a"))
        #expect(arguments == ["-f", "m4af", "-d", "aac", "-b", "96000", "/tmp/a.wav", "/tmp/b.m4a"])
    }

    @Test(.enabled(if: hasFFmpeg)) func compressesAudioToTheChosenBitrate() async throws {
        let folder = try workspace()
        let wav = folder.appendingPathComponent("tone.wav")
        try Self.run(Self.ffmpeg, ["-i", folder.appendingPathComponent("tone.m4a").path, "-c:a", "pcm_s16le", wav.path])
        let output = try await MediaTools.compressAudio(wav, kilobits: 64, tools: tools) { _ in }
        #expect(output.lastPathComponent == "tone 64k.m4a")
        let audio = try #require(try await probe(output).audio.first)
        #expect(audio.codec == "aac")
        // Apple's encoder averages the rate, so simple sound comes in under it.
        #expect((audio.bitRate ?? .max) <= 70_000)

        // Ogg isn't Apple's; ffmpeg does it.
        let ogg = folder.appendingPathComponent("tone.ogg")
        try Self.run(Self.ffmpeg, ["-i", wav.path, "-c:a", "libopus", ogg.path])
        let fromOgg = try await MediaTools.compressAudio(ogg, kilobits: 96, tools: tools) { _ in }
        #expect(try await probe(fromOgg).audio.first?.codec == "aac")
    }

    // MARK: Frame rate

    @Test(.enabled(if: hasFFmpeg)) func changesTheFrameRateKeepingTheLength() async throws {
        let folder = try workspace()
        let output = try await MediaTools.changeFrameRate(folder.appendingPathComponent("clip.mp4"), to: 60, tools: tools) { _ in }
        #expect(output.lastPathComponent == "clip 60fps.mp4")
        let probed = try await probe(output)
        #expect(probed.video?.framesPerSecond == 60)
        #expect(abs(probed.duration - 3) < 0.1)
        #expect(probed.audio.first?.codec == "aac")
    }

    // MARK: Animated PNG from video

    @Test(.enabled(if: hasFFmpeg)) func videoBecomesAnAnimatedPNG() async throws {
        let folder = try workspace()
        let output = try await MediaConversion.convert(folder.appendingPathComponent("clip.mp4"), to: .apng, tools: tools) { _ in }
        #expect(output.lastPathComponent == "clip.png")
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        // 3 seconds at 12 fps.
        #expect(CGImageSourceGetCount(source) >= 30)
    }

    // MARK: Export

    @Test func containersHoldTheirCodecs() {
        #expect(VideoContainer.webm.codecs == [.vp9, .av1])
        #expect(!VideoContainer.mp4.codecs.contains(.prores))
        let arguments = FFmpegEdits.export(container: .webm, codec: .vp9)
        #expect(arguments.contains("libvpx-vp9") && arguments.contains("libopus") && !arguments.contains("+faststart"))
        #expect(FFmpegEdits.export(container: .mov, codec: .prores).contains("prores_ks"))
    }

    @Test(.enabled(if: hasFFmpeg)) func exportsInEachCodec() async throws {
        let folder = try workspace()
        let clip = folder.appendingPathComponent("clip.mp4")
        let cases: [(VideoContainer, VideoCodec, String, String)] = [
            (.mkv, .av1, "clip AV1.mkv", "av1"),
            (.webm, .vp9, "clip VP9.webm", "vp9"),
            (.mov, .prores, "clip ProRes.mov", "prores"),
            (.mp4, .hevc, "clip HEVC.mp4", "hevc"),
        ]
        for (container, codec, name, probedCodec) in cases {
            let output = try await MediaTools.exportVideo(clip, as: container, codec: codec, tools: tools) { _ in }
            #expect(output.lastPathComponent == name)
            let probed = try await probe(output)
            #expect(probed.video?.codec == probedCodec, "\(name)")
            #expect(probed.audio.count == 1, "\(name)")
        }
        await #expect(throws: ConversionError.self) {
            try await MediaTools.exportVideo(clip, as: .webm, codec: .h264, tools: tools) { _ in }
        }
    }

    @Test(.enabled(if: hasFFmpeg)) func exportsSoundInEachFormat() async throws {
        let folder = try workspace()
        let tone = folder.appendingPathComponent("tone.m4a")
        let expected: [(AudioExportFormat, String, String)] = [
            (.aac, "tone AAC.m4a", "aac"), (.alac, "tone ALAC.m4a", "alac"), (.caf, "tone CAF.caf", "alac"),
            (.pcm, "tone PCM.wav", "pcm_s24le"), (.vorbis, "tone Vorbis.ogg", "vorbis"),
        ]
        for (format, name, codec) in expected {
            let output = try await MediaTools.exportAudio(tone, as: format, tools: tools) { _ in }
            #expect(output.lastPathComponent == name)
            #expect(try await probe(output).audio.first?.codec == codec, "\(name)")
        }
        // A file Apple doesn't read goes through ffmpeg.
        let ogg = folder.appendingPathComponent("tone.ogg")
        try Self.run(Self.ffmpeg, ["-i", tone.path, "-c:a", "libopus", ogg.path])
        let alac = try await MediaTools.exportAudio(ogg, as: .alac, tools: tools) { _ in }
        #expect(try await probe(alac).audio.first?.codec == "alac")
    }

    @Test(.enabled(if: hasFFmpeg)) func exportsBroadcastAndDiscContainers() async throws {
        let folder = try workspace()
        let clip = folder.appendingPathComponent("clip.mp4")
        let cases: [(VideoContainer, VideoCodec, String, String, String)] = [
            (.mpeg, .mpeg2, "clip MPEG-2.mpg", "mpeg2video", "mp2"),
            (.vob, .mpeg2, "clip MPEG-2.vob", "mpeg2video", "ac3"),
            (.ts, .h264, "clip H.264.ts", "h264", "aac"),
            (.m2ts, .hevc, "clip HEVC.m2ts", "hevc", "aac"),
        ]
        for (container, codec, name, videoCodec, audioCodec) in cases {
            let output = try await MediaTools.exportVideo(clip, as: container, codec: codec, tools: tools) { _ in }
            #expect(output.lastPathComponent == name)
            let probed = try await probe(output)
            #expect(probed.video?.codec == videoCodec && probed.audio.first?.codec == audioCodec, "\(name)")
        }
        let mka = try await MediaTools.exportAudio(folder.appendingPathComponent("tone.m4a"), as: .mka, tools: tools) { _ in }
        #expect(mka.lastPathComponent == "tone MKA.mka")
        #expect(try await probe(mka).audio.first?.codec == "aac")
    }
}
