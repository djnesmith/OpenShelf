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
        let sound = soundPlan(url, probed: probed, ffmpeg: ffmpeg)
        let destination = OutputNaming.destination(for: url, suffix: "Reversed", pathExtension: sound.container)
        try SaveError.checkWritable(destination)
        try await FFmpegJob.export(ffmpeg, ["-i", url.path] + FFmpegEdits.reverse(probed, container: sound.container, audio: sound.encode), to: destination, duration: probed.duration, progress: progress)
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

    // MARK: Mono

    /// The first sound track mixed down to one channel.
    static func mono(_ url: URL, tools: ExternalTools = .current, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard var track = probed.audio.first else { throw MediaToolError.noTracks(url) }
        track.channels = 1
        let plan = KeepFormat.audio(for: url, track: track, encoders: FFmpegEncoders.available(in: ffmpeg))
        let destination = OutputNaming.destination(for: url, suffix: "Mono", pathExtension: plan.pathExtension)
        try SaveError.checkWritable(destination)
        let arguments: [String] = ["-i", url.path, "-map", "0:a:0", "-vn", "-ac", "1"] + plan.arguments(index: 0)
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    // MARK: Normalize loudness

    /// Every sound track brought to -16 LUFS (EBU R128), the level podcasts
    /// and streaming use. A video's picture is copied as it is.
    static func normalizeLoudness(_ url: URL, tools: ExternalTools = .current, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        let sound = soundPlan(url, probed: probed, ffmpeg: ffmpeg)
        let destination = OutputNaming.destination(for: url, suffix: "Normalized", pathExtension: sound.container)
        try SaveError.checkWritable(destination)
        let arguments: [String] = ["-i", url.path] + FFmpegEdits.normalizeLoudness(probed, audio: sound.encode)
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    // MARK: Volume

    /// Every sound track made `decibels` louder (or quieter, below 0), with a
    /// limiter so a boost can't clip. A video's picture is copied as it is.
    static func changeVolume(
        _ url: URL,
        by decibels: Int,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
        let sound = soundPlan(url, probed: probed, ffmpeg: ffmpeg)
        let destination = OutputNaming.destination(for: url, suffix: decibels > 0 ? "Louder" : "Quieter", pathExtension: sound.container)
        try SaveError.checkWritable(destination)
        let arguments: [String] = ["-i", url.path] + FFmpegEdits.volume(probed, decibels: decibels, audio: sound.encode)
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    // MARK: Frame rate

    static let frameRates: [Int] = [24, 25, 30, 50, 60]

    /// The picture re-timed to `fps` frames a second (frames dropped or
    /// repeated, the length unchanged); sound is copied.
    static func changeFrameRate(
        _ url: URL,
        to fps: Int,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let ffmpeg = try requireFFmpeg(tools)
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard let video = probed.video else { throw MediaToolError.noVideo(url) }
        let destination = OutputNaming.destination(for: url, suffix: "\(fps)fps", pathExtension: KeepFormat.container(for: url))
        try SaveError.checkWritable(destination)
        let arguments: [String] = ["-i", url.path, "-map", "0:V:0", "-map", "0:a?", "-vf", "fps=\(fps)"]
            + FFmpegEdits.videoEncoding(for: video, container: KeepFormat.container(for: url)) + FFmpegEdits.audioCopyOrAAC(probed.audio, container: KeepFormat.container(for: url))
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        return destination
    }

    /// Where re-encoded sound goes and how each track is written: an audio
    /// file keeps its own format (see `KeepFormat`); a video keeps its container.
    static func soundPlan(_ url: URL, probed: ProbedMedia, ffmpeg: URL) -> (container: String, encode: @Sendable (Int, ProbedMedia.Audio) -> [String]) {
        if probed.video != nil {
            let container = KeepFormat.container(for: url)
            return (container, { index, track in FFmpegEdits.filteredAudio(container, track: track, index: index) })
        }
        let plan = KeepFormat.audio(for: url, track: probed.audio.first, encoders: FFmpegEncoders.available(in: ffmpeg))
        return (plan.pathExtension, { index, _ in plan.arguments(index: index) })
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
    static func reverse(_ probed: ProbedMedia, container: String = "mp4", audio: (Int, ProbedMedia.Audio) -> [String] = { aac($1, index: $0) }) -> [String] {
        var graph: [String] = []
        var arguments: [String] = []
        if let video = probed.video {
            graph.append("[0:V:0]reverse[v]")
            arguments += ["-map", "[v]"] + videoEncoding(for: video, container: container)
        }
        for (index, track) in probed.audio.enumerated() {
            graph.append("[0:a:\(index)]areverse[a\(index)]")
            arguments += ["-map", "[a\(index)]"] + audio(index, track)
        }
        return ["-filter_complex", graph.joined(separator: ";")] + arguments
    }

    // MARK: Sound filters

    /// The range the Volume tool offers, in dB.
    static let volumeRange: ClosedRange<Int> = -20...20

    /// Every sound track's gain changed by `decibels`, then through
    /// `alimiter` holding peaks at -1 dBFS (0.891), without its automatic
    /// levelling, so loud parts flatten instead of clipping. A picture is copied.
    static func volume(_ probed: ProbedMedia, decibels: Int, audio: (Int, ProbedMedia.Audio) -> [String]) -> [String] {
        var graph: [String] = []
        var arguments: [String] = []
        if let video = probed.video {
            arguments += ["-map", "0:V:0"] + videoCopy(for: video)
        }
        for (index, track) in probed.audio.enumerated() {
            graph.append("[0:a:\(index)]volume=\(decibels)dB,alimiter=limit=0.891:level=false[a\(index)]")
            arguments += ["-map", "[a\(index)]"] + audio(index, track)
        }
        return ["-filter_complex", graph.joined(separator: ";")] + arguments
    }

    /// Target loudness for `normalizeLoudness`, in LUFS.
    static let loudnessTarget = -16

    /// Every sound track through ffmpeg's one-pass `loudnorm`, resampled back
    /// to its own rate (loudnorm works at 192 kHz). A picture is copied.
    static func normalizeLoudness(_ probed: ProbedMedia, audio: (Int, ProbedMedia.Audio) -> [String]) -> [String] {
        var graph: [String] = []
        var arguments: [String] = []
        if let video = probed.video {
            arguments += ["-map", "0:V:0"] + videoCopy(for: video)
        }
        for (index, track) in probed.audio.enumerated() {
            let rate = Int((track.sampleRate ?? 48_000).rounded())
            graph.append("[0:a:\(index)]loudnorm=I=\(loudnessTarget):TP=-1.5:LRA=11,aresample=\(rate)[a\(index)]")
            arguments += ["-map", "[a\(index)]"] + audio(index, track)
        }
        return ["-filter_complex", graph.joined(separator: ";")] + arguments
    }

    /// Where filtered sound goes: WAV, AIFF and FLAC stay as they are; the
    /// rest (MP3, Ogg, CAF…) become M4A.
    static func filteredAudioContainer(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav", "wave": "wav"
        case "aif", "aiff", "flac": url.pathExtension.lowercased()
        default: "m4a"
        }
    }

    /// The codec for filtered sound in `container`: lossless containers stay
    /// lossless, and a video's sound keeps its codec when the container holds it.
    static func filteredAudio(_ container: String, track: ProbedMedia.Audio, index: Int) -> [String] {
        if ["mp4", "m4v", "mov", "mkv", "webm", "avi"].contains(container), KeepFormat.holds(container, audio: track.codec), let encoder = KeepFormat.encoder(forAudioCodec: track.codec) {
            let rate: [String] = ["aac", "libmp3lame", "ac3", "eac3", "libopus"].contains(encoder) ? ["-b:a:\(index)", "\(track.bitRate ?? AudioBitRate.target(for: .aac, source: track.source))"] : []
            // ffmpeg's own Vorbis encoder is experimental and stereo only.
            let vorbis: [String] = encoder == "vorbis" ? ["-strict", "experimental", "-ac:a:\(index)", "2"] : []
            return ["-c:a:\(index)", encoder] + rate + vorbis
        }
        return switch container {
        case "wav": ["-c:a:\(index)", "pcm_s16le"]
        case "aif", "aiff": ["-c:a:\(index)", "pcm_s16be"]
        case "flac": ["-c:a:\(index)", "flac"]
        default: aac(track, index: index)
        }
    }
}
