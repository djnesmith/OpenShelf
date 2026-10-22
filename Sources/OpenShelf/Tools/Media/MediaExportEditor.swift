import Observation
import SwiftUI

/// Saves videos in another file type and codec.
struct MediaExportEditor: View {
    static let windowSize = CGSize(width: 440, height: 280)

    let actions: EditorActions
    @State private var model: MediaExportModel

    init(urls: [URL], actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: MediaExportModel(urls: urls))
    }

    var body: some View {
        EditorChrome(
            title: "Export",
            primaryTitle: "Save",
            isPrimaryEnabled: model.progress == nil && model.isValid,
            actions: actions,
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "File type") {
                    Picker("File type", selection: $model.container) {
                        ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: model.container) { _, _ in model.pickUsableCodec() }
                }
                EditorRow(label: "Video") {
                    Picker("Video codec", selection: $model.codec) {
                        ForEach(model.codecs) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let progress = model.progress {
                    MediaExportProgress(progress: progress, detail: model.detail)
                }
                Spacer(minLength: 0)
            }
        }
        .onDisappear(perform: model.cancel)
    }
}

@MainActor
@Observable
final class MediaExportModel {
    let urls: [URL]
    var container = VideoContainer.mp4
    var codec = VideoCodec.h264
    private(set) var progress: Double?
    private(set) var detail: String?
    /// Encoders this ffmpeg has.
    private let encoders: Set<String>
    @ObservationIgnored private var task: Task<Void, Never>?

    init(urls: [URL], tools: ExternalTools = .current) {
        self.urls = urls
        encoders = tools.ffmpeg.map(FFmpegEncoders.available(in:)) ?? []
    }

    var title: String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
    }

    var codecs: [VideoCodec] {
        container.codecs.filter { encoders.contains($0.encoder) }
    }

    var isValid: Bool { codecs.contains(codec) }

    func pickUsableCodec() {
        if !codecs.contains(codec), let first = codecs.first { codec = first }
    }

    func cancel() {
        task?.cancel()
    }

    func save(actions: EditorActions) {
        progress = 0
        let urls = urls
        let container = container
        let codec = codec
        task = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, url) in urls.enumerated() {
                    self?.detail = urls.count > 1 ? "Exporting \(index + 1) of \(urls.count)…" : nil
                    outputs.append(try await MediaTools.exportVideo(url, as: container, codec: codec) { fraction in
                        Task { @MainActor in self?.progress = (Double(index) + fraction) / Double(urls.count) }
                    })
                }
                actions.saved(outputs)
            } catch is CancellationError {
                self?.progress = nil
            } catch {
                self?.progress = nil
                self?.detail = nil
                actions.failed(error)
            }
        }
    }
}
