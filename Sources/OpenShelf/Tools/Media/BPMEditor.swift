import SwiftUI

/// The audio "BPM" tool: a read-only list of each file's tempo.
struct BPMEditor: View {
    static let windowSize = CGSize(width: 460, height: 320)

    let urls: [URL]
    let actions: EditorActions

    @State private var report: String?

    var body: some View {
        EditorChrome(
            title: "BPM",
            primaryTitle: "Done",
            actions: actions,
            onPrimary: actions.close
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tempo from aubio. It can read half or double the real tempo.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let report {
                    ScrollView {
                        Text(report)
                            .font(.system(size: 12).monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Listening…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .task {
            do {
                report = BPM.report(try await BPM.detect(urls))
            } catch is CancellationError {
            } catch {
                actions.failed(error)
            }
        }
    }
}
