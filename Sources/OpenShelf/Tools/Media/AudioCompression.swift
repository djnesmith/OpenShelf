import Foundation
import Observation
import SwiftUI

extension MediaTools {
    // MARK: Compress audio

    static let audioBitRates: [Int] = [64, 96, 128, 160, 192, 256]

    /// AAC in M4A at `kilobits` per second: with macOS's own afconvert for
    /// files Apple reads (its default average-bitrate mode, so simple sound
    /// can come in under the rate), ffmpeg for the rest.
    static func compressAudio(
        _ url: URL,
        kilobits: Int,
        tools: ExternalTools = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = OutputNaming.destination(for: url, suffix: "\(kilobits)k", pathExtension: "m4a")
        try SaveError.checkWritable(destination)
        if MediaFormats.isAVFoundationReadable(url) {
            try await PartialFile.write(destination) { partial in
                try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/afconvert"), afconvertArguments(url, kilobits: kilobits, to: partial))
            }
            progress(1)
        } else {
            let ffmpeg = try requireFFmpeg(tools)
            let probed = try await ProbedMedia.load(url, ffprobe: tools.ffprobe)
            guard !probed.audio.isEmpty else { throw MediaToolError.noTracks(url) }
            let arguments = ["-i", url.path, "-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "\(kilobits)k"]
            try await FFmpegJob.export(ffmpeg, arguments, to: destination, duration: probed.duration, progress: progress)
        }
        return destination
    }

    static func afconvertArguments(_ url: URL, kilobits: Int, to output: URL) -> [String] {
        ["-f", "m4af", "-d", "aac", "-b", "\(kilobits * 1000)", url.path, output.path]
    }
}

/// Re-encodes audio files as AAC at a chosen bitrate.
struct AudioCompressEditor: View {
    static let windowSize = CGSize(width: 420, height: 240)

    let actions: EditorActions
    @State private var model: AudioCompressModel

    init(urls: [URL], actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: AudioCompressModel(urls: urls))
    }

    var body: some View {
        EditorChrome(
            title: "Compress",
            primaryTitle: "Save",
            isPrimaryEnabled: model.progress == nil,
            actions: actions,
            onReset: { model.kilobits = 128 },
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Bitrate") {
                    Picker("Bitrate", selection: $model.kilobits) {
                        ForEach(MediaTools.audioBitRates, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("kbps").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Saved as AAC (M4A). 128 kbps suits most music; 64–96 is fine for speech.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let progress = model.progress {
                    MediaExportProgress(progress: progress)
                }
                Spacer(minLength: 0)
            }
        }
        .onDisappear(perform: model.cancel)
    }
}

@MainActor
@Observable
final class AudioCompressModel {
    let urls: [URL]
    var kilobits = 128
    private(set) var progress: Double?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(urls: [URL]) {
        self.urls = urls
    }

    var title: String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
    }

    func cancel() {
        task?.cancel()
    }

    func save(actions: EditorActions) {
        progress = 0
        let urls = urls
        let kilobits = kilobits
        task = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, url) in urls.enumerated() {
                    outputs.append(try await MediaTools.compressAudio(url, kilobits: kilobits) { fraction in
                        Task { @MainActor in self?.progress = (Double(index) + fraction) / Double(urls.count) }
                    })
                }
                actions.saved(outputs)
            } catch is CancellationError {
                self?.progress = nil
            } catch {
                self?.progress = nil
                actions.failed(error)
            }
        }
    }
}
