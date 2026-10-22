@preconcurrency import AVFoundation
import Foundation

/// Edits (Reverse, Trim, Speed, Mono, Loudness, Volume…) save in the format
/// they were given: an MP3 stays an MP3, at about its own bitrate. Only when
/// that format can't be written does the edit fall back to M4A, and the saved
/// toast says why. Convert, Export, Compress and Fit Size choose a format on
/// purpose and don't use this.
enum KeepFormat {
    /// How one sound track is written.
    struct Audio: Equatable, Sendable {
        var pathExtension: String
        var encoder: String
        /// Bits per second, for a constant bitrate.
        var bitRate: Int?
        /// ffmpeg's VBR quality (`-q:a`), instead of a bitrate.
        var quality: String?
        var sampleRate: Int?
        var extra: [String] = []

        /// The arguments for output track `index`.
        func arguments(index: Int) -> [String] {
            var arguments = ["-c:a:\(index)", encoder]
            if let bitRate { arguments += ["-b:a:\(index)", "\(bitRate)"] }
            if let quality { arguments += ["-q:a:\(index)", quality] }
            if let sampleRate { arguments += ["-ar:a:\(index)", "\(sampleRate)"] }
            return arguments + extra
        }
    }

    /// MP3's constant bitrates, in kbps. An average elsewhere means the source was VBR.
    static let mp3ConstantRates: Set<Int> = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]

    /// The way to write an edited copy of the audio file `url` whose first
    /// track is `track`, with the encoders `encoders` this ffmpeg has.
    static func audio(for url: URL, track: ProbedMedia.Audio?, encoders: Set<String>) -> Audio {
        let pathExtension = url.pathExtension.lowercased()
        let codec = track?.codec ?? ""
        let sampleRate = track?.sampleRate.map { Int($0.rounded()) }
        func plan(_ encoder: String, bitRate: Int? = nil, quality: String? = nil, extra: [String] = []) -> Audio? {
            guard encoders.contains(encoder) else { return nil }
            return Audio(pathExtension: pathExtension, encoder: encoder, bitRate: bitRate, quality: quality, sampleRate: sampleRate, extra: extra)
        }
        let lossyRate = track.map { AudioBitRate.target(for: .aac, source: $0.source) }

        let kept: Audio? = switch pathExtension {
        case "mp3": mp3(track: track, encoders: encoders, sampleRate: sampleRate)
        case "m4a", "m4b", "aac", "mp4": codec == "alac" ? plan("alac") : plan("aac", bitRate: track?.bitRate ?? lossyRate)
        case "wav", "wave", "aif", "aiff": plan(codec.hasPrefix("pcm_") ? codec : (pathExtension.hasPrefix("ai") ? "pcm_s16be" : "pcm_s16le"))
        case "flac": plan("flac")
        case "caf": ["alac", "aac"].contains(codec) || codec.hasPrefix("pcm_") ? plan(codec, bitRate: codec == "aac" ? track?.bitRate : nil) : plan("alac")
        case "ogg", "oga":
            switch codec {
            case "opus": plan("libopus", bitRate: track?.bitRate)
            case "flac": plan("flac")
            // ffmpeg's own Vorbis encoder when libvorbis is missing: stereo only.
            default: plan("libvorbis", bitRate: track?.bitRate) ?? plan("vorbis", extra: ["-strict", "experimental", "-ac", "2"])
            }
        case "opus": plan("libopus", bitRate: track?.bitRate)
        case "wma": plan("wmav2", bitRate: track?.bitRate)
        default: nil
        }
        if let kept { return kept }
        return Audio(pathExtension: "m4a", encoder: "aac", bitRate: lossyRate, sampleRate: sampleRate)
    }

    /// MP3 at the source's bitrate, or at matching VBR quality when its
    /// average isn't one of MP3's constant rates.
    private static func mp3(track: ProbedMedia.Audio?, encoders: Set<String>, sampleRate: Int?) -> Audio? {
        guard encoders.contains("libmp3lame") else { return nil }
        guard let bitRate = track?.bitRate else {
            return Audio(pathExtension: "mp3", encoder: "libmp3lame", quality: "2", sampleRate: sampleRate)
        }
        let kilobits = Int((Double(bitRate) / 1000).rounded())
        if mp3ConstantRates.contains(kilobits) {
            return Audio(pathExtension: "mp3", encoder: "libmp3lame", bitRate: kilobits * 1000, sampleRate: sampleRate)
        }
        // LAME's V0 averages about 245 kbps, V2 190, V4 165, V6 130.
        let quality = switch kilobits {
        case 220...: "0"
        case 180..<220: "2"
        case 150..<180: "4"
        default: "6"
        }
        return Audio(pathExtension: "mp3", encoder: "libmp3lame", quality: quality, sampleRate: sampleRate)
    }

    // MARK: Video

    /// Video containers only ffmpeg edits.
    static let ffmpegContainers: Set<String> = ["mkv", "webm", "avi"]

    static func isFFmpegContainer(_ url: URL) -> Bool {
        ffmpegContainers.contains(url.resolvingSymlinksInPath().pathExtension.lowercased())
    }

    /// The container an ffmpeg edit of the video `url` writes: its own.
    static func container(for url: URL) -> String {
        isFFmpegContainer(url) ? url.pathExtension.lowercased() : MediaTools.videoContainer(for: url).pathExtension
    }

    /// Whether a video container holds sound in `codec`, so an edit can keep it.
    static func holds(_ container: String, audio codec: String) -> Bool {
        let mp4: Set<String> = ["aac", "alac", "mp3", "ac3", "eac3", "flac", "opus"]
        switch container {
        case "mp4", "m4v": return mp4.contains(codec)
        case "mov": return mp4.contains(codec) || codec.hasPrefix("pcm_")
        case "mkv": return true
        case "webm": return ["opus", "vorbis"].contains(codec)
        case "avi": return ["mp3", "ac3", "aac"].contains(codec) || codec.hasPrefix("pcm_")
        default: return false
        }
    }

    /// ffmpeg's encoder for re-encoding sound in `codec`.
    static func encoder(forAudioCodec codec: String) -> String? {
        switch codec {
        case "aac", "alac", "ac3", "eac3", "flac": codec
        case "mp3": "libmp3lame"
        case "opus": "libopus"
        case "vorbis": "vorbis"
        default: codec.hasPrefix("pcm_") ? codec : nil
        }
    }

    /// AVFoundation's presets for re-encoding a picture in `codec` (a
    /// CMFormatDescription subtype), best first: HEVC stays HEVC and ProRes
    /// stays ProRes (in MOV); the rest become H.264.
    static func presets(forVideoCodec codec: FourCharCode?) -> [String] {
        switch codec {
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha:
            [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        case kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ:
            [AVAssetExportPresetAppleProRes4444LPCM, AVAssetExportPresetAppleProRes422LPCM, AVAssetExportPresetHighestQuality]
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ, kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy:
            [AVAssetExportPresetAppleProRes422LPCM, AVAssetExportPresetHighestQuality]
        default:
            [AVAssetExportPresetHighestQuality]
        }
    }

    /// AVFoundation's one ProRes 422 preset writes 422 Standard (and its 4444
    /// preset 4444), so re-encoding any other ProRes flavour there would change
    /// it. Those go through ffmpeg, which keeps the profile.
    static func avFoundationChangesProRes(_ url: URL) async -> Bool {
        let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        guard let description = try? await track?.load(.formatDescriptions).first else { return false }
        return [kCMVideoCodecType_AppleProRes422HQ, kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy, kCMVideoCodecType_AppleProRes4444XQ]
            .contains(CMFormatDescriptionGetMediaSubType(description))
    }

    /// `presets(forVideoCodec:)` for the first picture track of `asset`.
    static func reencodePresets(for asset: AVAsset) async -> [String] {
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let description = try? await track?.load(.formatDescriptions).first
        return presets(forVideoCodec: description.map(CMFormatDescriptionGetMediaSubType))
    }

    /// The toast detail for an edit of `source` saved as `output`, when the
    /// format had to change; nil when it was kept.
    static func note(source: URL, output: URL, tools: ExternalTools = .current) -> String? {
        let from = source.pathExtension.lowercased(), to = output.pathExtension.lowercased()
        guard from != to, !(from == "m4b" && to == "m4a") else {
            return videoCodecNote(source: source, output: output, tools: tools)
        }
        return tools.ffmpeg == nil
            ? "Saved as \(to.uppercased()): keeping \(from.uppercased()) needs ffmpeg."
            : "Saved as \(to.uppercased()): OpenShelf can’t write \(from.uppercased()) here."
    }

    /// When the container was kept but the picture's codec changed: "Video
    /// saved as H.264: this edit can't write VP9 here." Needs ffprobe to tell.
    private static func videoCodecNote(source: URL, output: URL, tools: ExternalTools) -> String? {
        guard let ffprobe = tools.ffprobe else { return nil }
        func codec(_ url: URL) -> String? {
            MediaProbe.runSync(ffprobe, ["-v", "error", "-select_streams", "V:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0", url.path])?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        guard let before = codec(source), let after = codec(output), before != after else { return nil }
        return "Video saved as \(title(ofVideoCodec: after)): this edit can’t write \(title(ofVideoCodec: before)) here."
    }

    static func title(ofVideoCodec codec: String) -> String {
        switch codec {
        case "h264": "H.264"
        case "hevc": "HEVC"
        case "prores": "ProRes"
        case "mpeg4": "MPEG-4"
        case "mpeg2video": "MPEG-2"
        default: codec.uppercased()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
