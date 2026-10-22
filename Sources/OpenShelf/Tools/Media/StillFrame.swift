@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

extension MediaTools {
    // MARK: Still frame

    /// Saves the frame shown at `seconds` as a full-size image beside the video,
    /// e.g. "Clip Frame 12.5s.png".
    static func stillFrame(
        _ url: URL,
        at seconds: Double,
        as type: UTType = .png,
        tools: ExternalTools = .current
    ) async throws -> URL {
        let image = try await frame(of: url, at: seconds, maximumSize: nil, tools: tools)
        let pathExtension = type.preferredFilenameExtension ?? "png"
        let destination = OutputNaming.destination(for: url, suffix: stillFrameSuffix(seconds), pathExtension: pathExtension)
        try EditableImage.write(image, to: destination, type: type, quality: 0.95)
        return destination
    }

    /// The upright frame at `seconds`, exact rather than the nearest keyframe,
    /// fitted inside `maximumSize` when given.
    static func frame(of url: URL, at seconds: Double, maximumSize: CGFloat?, tools: ExternalTools = .current) async throws -> CGImage {
        try await MediaFallback.run(url, tools: tools) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            if let maximumSize {
                generator.maximumSize = CGSize(width: maximumSize, height: maximumSize)
            }
            return try await generator.image(at: MediaTime.cmTime(seconds)).image
        } fallback: { ffmpeg in
            try await MediaLoading.frame(of: url, at: seconds, maximumSize: maximumSize ?? 16_384, ffmpeg: ffmpeg)
        }
    }

    /// "Frame 12.5s": the time in the name, without characters Finder dislikes.
    static func stillFrameSuffix(_ seconds: Double) -> String {
        "Frame \(FFmpegEdits.factor((MediaTime.snapped(max(seconds, 0)) * 10).rounded() / 10))s"
    }
}
