import Observation
import SwiftUI

/// Re-times videos to a chosen frame rate.
struct FrameRateEditor: View {
    static let windowSize = CGSize(width: 420, height: 230)

    let actions: EditorActions
    @State private var model: FrameRateModel

    init(urls: [URL], actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: FrameRateModel(urls: urls))
    }

    var body: some View {
        EditorChrome(
            title: "Frame Rate",
            primaryTitle: "Save",
            isPrimaryEnabled: model.progress == nil,
            actions: actions,
            onReset: { model.fps = 30 },
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Frames/s") {
                    Picker("Frames per second", selection: $model.fps) {
                        ForEach(MediaTools.frameRates, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text("The length stays the same; frames are dropped or repeated. Sound is kept.")
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
final class FrameRateModel {
    let urls: [URL]
    var fps = 30
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
        let fps = fps
        task = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, url) in urls.enumerated() {
                    outputs.append(try await MediaTools.changeFrameRate(url, to: fps) { fraction in
                        Task { @MainActor in self?.progress = (Double(index) + fraction) / Double(urls.count) }
                    })
                }
                actions.saved(outputs, editing: urls[0])
            } catch is CancellationError {
                self?.progress = nil
            } catch {
                self?.progress = nil
                actions.failed(error)
            }
        }
    }
}
