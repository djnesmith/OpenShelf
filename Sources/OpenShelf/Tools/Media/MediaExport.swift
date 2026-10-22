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

/// What the Export tool can turn sound into.
enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case aac, alac, caf, pcm, vorbis

    var id: Self { self }

    var title: String {
        switch self {
        case .aac: "AAC"
        case .alac: "ALAC"
        case .caf: "CAF"
        case .pcm: "PCM"
        case .vorbis: "Vorbis"
        }
    }

    /// What it is, under the picker.
    var detail: String {
        switch self {
        case .aac: "AAC at 192 kbps in M4A: small, plays everywhere."
        case .alac: "Apple Lossless in M4A: exact, about half the size of WAV."
        case .caf: "Apple Lossless in a Core Audio file, for Logic and GarageBand."
        case .pcm: "Uncompressed 24-bit WAV."
        case .vorbis: "Ogg Vorbis, for games and open-source players. Needs ffmpeg."
        }
    }

    var pathExtension: String {
        switch self {
        case .aac, .alac: "m4a"
        case .caf: "caf"
        case .pcm: "wav"
        case .vorbis: "ogg"
        }
    }

    /// macOS's afconvert writes all but Vorbis, for files Apple reads.
    var afconvertArguments: [String]? {
        switch self {
        case .aac: ["-f", "m4af", "-d", "aac", "-b", "192000"]
        case .alac: ["-f", "m4af", "-d", "alac"]
        case .caf: ["-f", "caff", "-d", "alac"]
        case .pcm: ["-f", "WAVE", "-d", "LEI24"]
        case .vorbis: nil
        }
    }

    /// The same through ffmpeg, for everything else. `encoders` picks Vorbis's encoder.
    func ffmpegArguments(encoders: Set<String>) -> [String] {
        switch self {
        case .aac: ["-c:a", "aac", "-b:a", "192k"]
        case .alac: ["-c:a", "alac"]
        case .caf: ["-c:a", "alac", "-f", "caf"]
        case .pcm: ["-c:a", "pcm_s24le"]
        // Really Vorbis, unlike the Convert wheel's OGG, which falls back to Opus:
        // ffmpeg's own encoder when libvorbis is missing (stereo only).
        case .vorbis: encoders.contains("libvorbis") ? ["-c:a", "libvorbis", "-q:a", "5"] : ["-c:a", "vorbis", "-strict", "experimental", "-ac", "2"]
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

extension MediaTools {
    /// The first sound track as `format`, saved as "<name> ALAC.m4a".
    static func exportAudio(
        _ url: URL,
        as format: AudioExportFormat,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = OutputNaming.destination(for: url, suffix: format.title, pathExtension: format.pathExtension)
        try SaveError.checkWritable(destination)
        if MediaFormats.isAVFoundationReadable(url), let arguments = format.afconvertArguments {
            try await PartialFile.write(destination) { partial in
                try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/afconvert"), arguments + [url.path, partial.path])
            }
            progress(1)
            return destination
        }
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        let arguments = ["-i", url.path, "-map", "0:a:0", "-vn"] + format.ffmpegArguments(encoders: FFmpegEncoders.available(in: ffmpeg))
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
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
