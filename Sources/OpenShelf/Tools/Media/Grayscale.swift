@preconcurrency import AVFoundation
import CoreImage
import Foundation

extension MediaTools {
    // MARK: Grayscale

    /// A black-and-white copy of a video. Sound is kept.
    static func grayscale(_ url: URL, tools: ExternalTools = .current, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let ffmpeg = tools.ffmpeg, await KeepFormat.avFoundationChangesProRes(url) {
            return try await grayscaleWithFFmpeg(url, ffmpeg: ffmpeg, tools: tools, progress: progress)
        }
        return try await MediaFallback.run(url, tools: tools) {
            try await grayscaleWithAVFoundation(url, progress: progress)
        } fallback: { ffmpeg in
            try await grayscaleWithFFmpeg(url, ffmpeg: ffmpeg, tools: tools, progress: progress)
        }
    }

    private static func grayscaleWithAVFoundation(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw MediaToolError.noVideo(url) }
        let videoComposition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let gray = request.sourceImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            request.finish(with: gray, context: nil)
        }
        let output = videoContainer(for: url)
        let destination = OutputNaming.destination(for: url, suffix: "Grayscale", pathExtension: output.pathExtension)
        try SaveError.checkWritable(destination)
        let session = try await makeSession(for: asset, presets: await KeepFormat.reencodePresets(for: asset), fileType: output.fileType)
        session.videoComposition = videoComposition
        try await export(session, to: destination, fileType: output.fileType, progress: progress)
        return destination
    }

    static func grayscaleWithFFmpeg(_ url: URL, ffmpeg: URL, tools: ExternalTools, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
        guard let video = probed.video else { throw MediaToolError.noVideo(url) }
        let destination = OutputNaming.destination(for: url, suffix: "Grayscale", pathExtension: KeepFormat.container(for: url))
        try SaveError.checkWritable(destination)
        var arguments: [String] = ["-i", url.path, "-map", "0:V:0", "-map", "0:a?", "-vf", "hue=s=0"]
        arguments += FFmpegEdits.videoEncoding(for: video, container: KeepFormat.container(for: url)) + FFmpegEdits.audioCopyOrAAC(probed.audio, container: KeepFormat.container(for: url))
        try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        return destination
    }
}
