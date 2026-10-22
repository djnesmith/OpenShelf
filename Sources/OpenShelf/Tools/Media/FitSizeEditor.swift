import Observation
import SwiftUI

/// Re-encodes videos and audio files to come in under a chosen size.
struct FitSizeEditor: View {
    static let windowSize = CGSize(width: 420, height: 280)
    static let presets: [Int] = [10, 25, 50]

    let actions: EditorActions
    @State private var model: FitSizeModel

    init(urls: [URL], actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: FitSizeModel(urls: urls))
    }

    var body: some View {
        EditorChrome(
            title: "Fit Size",
            primaryTitle: "Save",
            isPrimaryEnabled: model.exportProgress == nil && model.megabytes > 0,
            actions: actions,
            onReset: { model.megabytes = 25 },
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Under") {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button("\(preset) MB") { model.megabytes = preset }
                            .buttonStyle(.bordered)
                            .tint(model.megabytes == preset ? .accentColor : nil)
                    }
                    TextField("MB", value: $model.megabytes, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                    Text("MB").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("Video becomes H.264 MP4 and audio AAC M4A, at the quality that fits.")
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
final class FitSizeModel {
    let urls: [URL]
    var megabytes = 25
    private(set) var exportProgress: Double?
    private(set) var progressDetail: String?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init(urls: [URL]) {
        self.urls = urls
    }

    var title: String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
    }

    func cancel() {
        exportTask?.cancel()
    }

    func save(actions: EditorActions) {
        exportProgress = 0
        let urls = urls
        // ByteCountFormatter's MB: 1,000,000 bytes.
        let bytes = Int64(megabytes) * 1_000_000
        exportTask = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, url) in urls.enumerated() {
                    self?.progressDetail = urls.count > 1 ? "Exporting \(index + 1) of \(urls.count)…" : nil
                    outputs.append(try await MediaTools.fitSize(url, bytes: bytes) { fraction in
                        Task { @MainActor in self?.exportProgress = (Double(index) + fraction) / Double(urls.count) }
                    })
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
