import Foundation

/// Bitrates that bring a video or audio file in under a size.
struct FitSizePlan: Equatable, Sendable {
    /// Bits per second; nil for audio.
    var videoBitRate: Int?
    var audioBitRate: Int
    /// The tallest the picture may be; nil to keep its size.
    var maximumHeight: Int?

    /// A share of the size kept back for the container and encoder drift.
    static let headroom = 0.95
    static let minimumAudio = 32_000
    static let minimumVideo = 100_000

    /// Throws, saying the smallest size that works, when `bytes` is too small for `duration` seconds.
    static func make(bytes: Int64, duration: Double, hasVideo: Bool) throws -> FitSizePlan {
        guard duration > 0 else { throw MediaToolError.failed("This file has no length to fit.") }
        let bitsPerSecond = Int(Double(bytes) * 8 * headroom / duration)
        let floor = hasVideo ? minimumVideo + 64_000 : minimumAudio
        guard bitsPerSecond >= floor else {
            let needed = Double(floor) * duration / 8 / headroom
            throw MediaToolError.failed("Too long to fit. It needs at least \(megabytes(Int64(needed.rounded(.up)))).")
        }
        guard hasVideo else {
            return FitSizePlan(videoBitRate: nil, audioBitRate: min(bitsPerSecond, 320_000), maximumHeight: nil)
        }
        let audio = bitsPerSecond >= 1_500_000 ? 128_000 : bitsPerSecond >= 600_000 ? 96_000 : 64_000
        let video = bitsPerSecond - audio
        // Fewer bits look better on fewer pixels.
        let height: Int? = switch video {
        case 4_000_000...: nil
        case 2_000_000...: 1080
        case 1_000_000...: 720
        case 500_000...: 480
        default: 360
        }
        return FitSizePlan(videoBitRate: video, audioBitRate: audio, maximumHeight: height)
    }

    static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension MediaTools {
    // MARK: Fit size

    /// A copy under `bytes`: H.264 and AAC in MP4 for video (two-pass, so it
    /// lands close to the size), AAC in M4A for audio. Needs ffmpeg.
    static func fitSize(
        _ url: URL,
        bytes: Int64,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let original = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? .max
        guard original > bytes else {
            throw MediaToolError.failed("Already under \(FitSizePlan.megabytes(bytes)), so nothing was saved.")
        }
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard probed.video != nil || !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        let plan = try FitSizePlan.make(bytes: bytes, duration: probed.duration, hasVideo: probed.video != nil)
        let suffix = FitSizePlan.megabytes(bytes).replacingOccurrences(of: " ", with: "")
        let destination = OutputNaming.destination(for: url, suffix: suffix, pathExtension: probed.video != nil ? "mp4" : "m4a")
        try SaveError.checkWritable(destination)

        guard let video = probed.video, let videoBitRate = plan.videoBitRate else {
            let arguments = ["-i", url.path, "-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "\(plan.audioBitRate)"]
            try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
            return destination
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-2pass-\(UUID().uuidString)")
        defer { removePassLogs(log) }
        let common = FFmpegEdits.fitSizeVideo(plan: plan, videoBitRate: videoBitRate, sourceHeight: video.displaySize.height, passLog: log)
        try await FFmpegJob.run(ffmpeg, ["-i", url.path] + common + ["-pass", "1", "-an", "-f", "null"], output: URL(fileURLWithPath: "/dev/null"), duration: probed.duration) {
            progress($0 / 2)
        }
        let second = ["-i", url.path] + common + ["-pass", "2", "-map", "0:a:0?", "-c:a", "aac", "-b:a", "\(plan.audioBitRate)", "-movflags", "+faststart"]
        try await FFmpegJob.export(ffmpeg, second, to: destination, duration: probed.duration) { progress(0.5 + $0 / 2) }
        return destination
    }

    /// x264's two-pass statistics files ("<log>-0.log" and friends).
    private static func removePassLogs(_ log: URL) {
        let folder = log.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(log.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

extension FFmpegEdits {
    /// The picture's settings for both passes of a fit-size encode.
    static func fitSizeVideo(plan: FitSizePlan, videoBitRate: Int, sourceHeight: Double, passLog: URL) -> [String] {
        var arguments: [String] = ["-map", "0:V:0"]
        if let height = plan.maximumHeight, sourceHeight > Double(height) {
            arguments += ["-vf", "scale=-2:\(height)"]
        }
        return arguments + [
            "-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p",
            "-b:v", "\(videoBitRate)", "-maxrate", "\(videoBitRate * 3 / 2)", "-bufsize", "\(videoBitRate * 2)",
            "-passlogfile", passLog.path,
        ]
    }
}
