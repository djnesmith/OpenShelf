import Foundation

/// A picture codec the Export tool can write, through ffmpeg.
enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc, av1, vp9, prores

    var id: Self { self }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .av1: "AV1"
        case .vp9: "VP9"
        case .prores: "ProRes"
        }
    }

    /// The ffmpeg encoder, so the editor offers only what this ffmpeg has.
    var encoder: String {
        switch self {
        case .h264: "libx264"
        case .hevc: "libx265"
        case .av1: "libsvtav1"
        case .vp9: "libvpx-vp9"
        case .prores: "prores_ks"
        }
    }

    /// Good quality at a sensible size; ProRes 422 HQ for editing.
    var arguments: [String] {
        switch self {
        case .h264: ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"]
        case .hevc: ["-c:v", "libx265", "-preset", "medium", "-crf", "24", "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-x265-params", "log-level=error"]
        case .av1: ["-c:v", "libsvtav1", "-preset", "8", "-crf", "35", "-pix_fmt", "yuv420p"]
        case .vp9: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-deadline", "good", "-cpu-used", "4", "-row-mt", "1"]
        case .prores: ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
        }
    }
}

/// A file type the Export tool can write video into.
enum VideoContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4, mov, mkv, webm

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var pathExtension: String { rawValue }

    /// The codecs this container holds and players expect in it, first the usual one.
    var codecs: [VideoCodec] {
        switch self {
        case .mp4: [.h264, .hevc, .av1, .vp9]
        case .mov: [.h264, .hevc, .prores]
        case .mkv: [.h264, .hevc, .av1, .vp9, .prores]
        case .webm: [.vp9, .av1]
        }
    }

    /// Sound in the codec this container is expected to carry.
    var audioArguments: [String] {
        switch self {
        case .webm: ["-c:a", "libopus", "-b:a", "160k"]
        default: ["-c:a", "aac", "-b:a", "192k"]
        }
    }
}

extension MediaTools {
    // MARK: Export

    /// A copy of a video in `container`, its picture as `codec` and its sound
    /// in the container's usual codec. Saved as "<name> AV1.mkv".
    static func exportVideo(
        _ url: URL,
        as container: VideoContainer,
        codec: VideoCodec,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        guard container.codecs.contains(codec) else {
            throw ConversionError.unsupported("\(codec.title) in \(container.title)")
        }
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard probed.video != nil else { throw MediaToolError.noVideo(url) }
        let destination = OutputNaming.destination(for: url, suffix: codec.title, pathExtension: container.pathExtension)
        try SaveError.checkWritable(destination)
        try await FFmpegJob.export(ffmpeg, ["-i", url.path] + FFmpegEdits.export(container: container, codec: codec), to: destination, duration: probed.duration, progress: progress)
        return destination
    }
}

extension FFmpegEdits {
    static func export(container: VideoContainer, codec: VideoCodec) -> [String] {
        var arguments: [String] = ["-map", "0:V:0", "-map", "0:a?"] + codec.arguments + container.audioArguments
        if container == .mp4 || container == .mov {
            arguments += ["-movflags", "+faststart"]
        }
        return arguments
    }
}
