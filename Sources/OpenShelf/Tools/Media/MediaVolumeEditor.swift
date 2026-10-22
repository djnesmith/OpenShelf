import Observation
import SwiftUI

/// Makes videos and audio files louder or quieter.
struct MediaVolumeEditor: View {
    static let windowSize = CGSize(width: 420, height: 260)

    let actions: EditorActions
    @State private var model: VolumeModel

    init(urls: [URL], actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: VolumeModel(urls: urls))
    }

    var body: some View {
        EditorChrome(
            title: "Volume",
            primaryTitle: "Save",
            isPrimaryEnabled: model.exportProgress == nil && Int(model.decibels) != 0,
            actions: actions,
            onReset: { model.decibels = 6 },
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                EditorRow(label: "Volume") {
                    Slider(
                        value: $model.decibels,
                        in: Double(FFmpegEdits.volumeRange.lowerBound)...Double(FFmpegEdits.volumeRange.upperBound),
                        step: 1
                    )
                    .controlSize(.small)
                    Text(model.label)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                Text("A limiter keeps louder sound from distorting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let progress = model.exportProgress {
                    MediaExportProgress(progress: progress, detail: model.progressDetail)
                }
                Spacer(minLength: 0)
            }
        }
        .onDisappear(perform: model.cancel)
    }
}

@MainActor
@Observable
final class VolumeModel {
    let urls: [URL]
    var decibels: Double = 6
    private(set) var exportProgress: Double?
    private(set) var progressDetail: String?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init(urls: [URL]) {
        self.urls = urls
    }

    var title: String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
    }

    /// "+6 dB", "-3 dB", "0 dB".
    var label: String {
        let value = Int(decibels)
        return value > 0 ? "+\(value) dB" : "\(value) dB"
    }

    func cancel() {
        exportTask?.cancel()
    }

    func save(actions: EditorActions) {
        exportProgress = 0
        let urls = urls
        let decibels = Int(decibels)
        exportTask = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, url) in urls.enumerated() {
                    self?.progressDetail = urls.count > 1 ? "Exporting \(index + 1) of \(urls.count)…" : nil
                    let output = try await MediaTools.changeVolume(url, by: decibels) { fraction in
                        Task { @MainActor in self?.exportProgress = (Double(index) + fraction) / Double(urls.count) }
                    }
                    outputs.append(output)
                }
                actions.saved(outputs)
            } catch is CancellationError {
                self?.exportProgress = nil
            } catch {
                self?.exportProgress = nil
                self?.progressDetail = nil
                actions.failed(error)
            }
        }
    }
}
