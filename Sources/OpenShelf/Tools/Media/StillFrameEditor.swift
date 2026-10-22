import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Picks a moment in a video and saves that frame as an image.
struct StillFrameEditor: View {
    static let windowSize = CGSize(width: 460, height: 500)

    let actions: EditorActions
    @State private var model: StillFrameModel

    init(url: URL, actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: StillFrameModel(url: url))
    }

    var body: some View {
        EditorChrome(
            title: "Still Frame",
            primaryTitle: "Save Frame",
            isPrimaryEnabled: model.duration > 0 && !model.isSaving,
            actions: actions,
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(spacing: 14) {
                Group {
                    if let frame = model.preview {
                        Image(decorative: frame, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                    } else if let error = model.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.18)))

                HStack {
                    Slider(value: $model.time, in: 0...max(model.duration, 0.1))
                        .disabled(model.duration <= 0)
                        .accessibilityLabel("Time")
                    Text(MediaTime.format(model.time))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                }

                Picker("Format", selection: $model.format) {
                    Text("PNG").tag(UTType.png)
                    Text("JPEG").tag(UTType.jpeg)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer(minLength: 0)
            }
        }
        .task { await model.load() }
        .task(id: model.time) { await model.updatePreview() }
    }
}

@MainActor
@Observable
final class StillFrameModel {
    let url: URL
    var time: Double = 0
    var format = UTType.png
    private(set) var duration: Double = 0
    private(set) var preview: CGImage?
    private(set) var loadError: String?
    private(set) var isSaving = false

    init(url: URL) {
        self.url = url
    }

    func load() async {
        do {
            duration = try await MediaLoading.basics(of: url).duration
            time = MediaLoading.posterTime(duration)
        } catch {
            loadError = MediaLoading.loadError(error, otherwise: "This video can’t be read.")
        }
    }

    /// Shows the frame under the slider, after it has rested for a moment.
    func updatePreview() async {
        guard duration > 0 else { return }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        if let frame = try? await MediaTools.frame(of: url, at: time, maximumSize: 900) {
            preview = frame
        }
    }

    func save(actions: EditorActions) {
        isSaving = true
        let url = url
        let time = time
        let format = format
        Task { [weak self] in
            do {
                actions.saved([try await MediaTools.stillFrame(url, at: time, as: format)])
            } catch {
                self?.isSaving = false
                actions.failed(error)
            }
        }
    }
}
