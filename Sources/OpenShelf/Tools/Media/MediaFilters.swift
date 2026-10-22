import Foundation

/// One-click media edits that only ffmpeg does, so the Tools wheel offers
/// them only when ffmpeg is installed. Each writes a new file beside the
/// source through a hidden partial file, like the other media tools.
extension MediaTools {
    // MARK: Reverse

    /// Plays the whole file backwards: picture and sound.
    static func reverse(_ url: URL, tools: ExternalTools = .current, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard probed.video != nil || !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        try ReverseLimit.check(probed)
        let pathExtension = probed.video != nil ? videoContainer(for: url).pathExtension : "m4a"
        let destination = OutputNaming.destination(for: url, suffix: "Reversed", pathExtension: pathExtension)
        try SaveError.checkWritable(destination)
        try await FFmpegJob.export(ffmpeg, ["-i", url.path] + FFmpegEdits.reverse(probed), to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    // MARK: Strip metadata

    /// A copy without its tags (title, location, dates, camera), chapters,
    /// cover art or timed-metadata tracks. Picture and sound are copied as
    /// they are, so nothing is re-encoded; subtitles are left out.
    static func stripMetadata(_ url: URL, tools: ExternalTools = .current, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard probed.video != nil || !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        let destination = OutputNaming.destination(for: url, suffix: MetadataSuffix.removed, pathExtension: url.pathExtension.lowercased())
        try SaveError.checkWritable(destination)
        try await FFmpegJob.export(ffmpeg, ["-i", url.path] + FFmpegEdits.stripMetadata, to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    static func requireFFmpeg(_ tools: ExternalTools) throws -> URL {
        guard let ffmpeg = tools.ffmpeg else { throw MissingToolError(name: "ffmpeg") }
        return ffmpeg
    }
}

/// ffmpeg's reverse filters hold every decoded frame and sample in memory
/// before writing the first one, so long or large clips are refused up front
/// instead of exhausting the Mac's memory.
enum ReverseLimit {
    /// Decoded data a reverse may hold: 2 GB.
    static let maximumBytes: Double = 2_000_000_000

    /// Bytes ffmpeg holds to reverse `probed`: raw 4:2:0 frames (1.5 bytes a
    /// pixel), or 10-bit (3 bytes) for HDR, plus 32-bit float samples.
    static func estimatedBytes(_ probed: ProbedMedia) -> Double {
        var perSecond: Double = 0
        if let video = probed.video {
            let bytesPerPixel: Double = video.isHDR ? 3 : 1.5
            perSecond += Double(video.width * video.height) * bytesPerPixel * (video.framesPerSecond ?? 30)
        }
        for track in probed.audio {
            perSecond += (track.sampleRate ?? 48_000) * Double(track.channels) * 4
        }
        return perSecond * probed.duration
    }

    /// Throws, saying how long a clip of this kind may be, when `probed` is too big.
    static func check(_ probed: ProbedMedia) throws {
        let bytes = estimatedBytes(probed)
        guard bytes > maximumBytes else { return }
        let longest = probed.duration * maximumBytes / bytes
        throw MediaToolError.failed("Too long to reverse here. Trim it to under \(MediaTime.format(longest.rounded(.down))) first.")
    }
}

extension FFmpegEdits {
    /// Every picture and sound stream copied, with no global, stream or
    /// chapter metadata and no encoder tag.
    static let stripMetadata: [String] = [
        "-map", "0:V?", "-map", "0:a?", "-c", "copy",
        "-map_metadata", "-1", "-map_chapters", "-1",
        "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
    ]

    /// Picture and every sound track reversed; video re-encoded, sound as AAC.
    static func reverse(_ probed: ProbedMedia) -> [String] {
        var graph: [String] = []
        var arguments: [String] = []
        if let video = probed.video {
            graph.append("[0:V:0]reverse[v]")
            arguments += ["-map", "[v]"] + videoEncoding(for: video)
        }
        for (index, track) in probed.audio.enumerated() {
            graph.append("[0:a:\(index)]areverse[a\(index)]")
            arguments += ["-map", "[a\(index)]"] + aac(track, index: index)
        }
        return ["-filter_complex", graph.joined(separator: ";")] + arguments
    }
}
