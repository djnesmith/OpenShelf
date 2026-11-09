import SwiftUI

/// The PDF "Check Safety" tool: a read-only report on one or more PDFs.
struct CheckSafetyEditor: View {
    static let windowSize = CGSize(width: 520, height: 460)

    let urls: [URL]
    let actions: EditorActions

    @State private var report: String?

    var body: some View {
        EditorChrome(
            title: "Check Safety",
            primaryTitle: "Done",
            actions: actions,
            onPrimary: actions.close
        ) {
            VStack(alignment: .leading, spacing: 14) {
                PDFFileHeader(url: urls[0], detail: "Looks for JavaScript, embedded files and other active content", count: urls.count)
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
                        Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .task {
            do {
                report = CheckSafety.report(try await CheckSafety.check(urls))
            } catch is CancellationError {
            } catch {
                actions.failed(error)
            }
        }
    }
}
