import PDFKit
import SwiftUI

/// The PDF "Make Fillable" tool: a copy of one plain PDF with form fields
/// where its blanks, boxes and signature lines are.
struct MakeFillableEditor: View {
    static let windowSize = CGSize(width: 440, height: 300)

    let url: URL
    let actions: EditorActions

    @State private var pageCount: Int?
    @State private var isScanned = false
    @State private var hasFields = false
    @State private var isModelCached = MakeFillable.isModelCached()
    @State private var isWorking = false
    /// The run, stopped when the window closes so nothing is saved after "Close without saving".
    @State private var run: Task<Void, Never>?

    var body: some View {
        EditorChrome(
            title: "Make Fillable",
            primaryTitle: isWorking ? "Working…" : "Make Fillable",
            isPrimaryEnabled: !isWorking && !hasFields,
            actions: actions,
            onPrimary: makeFillable
        ) {
            VStack(alignment: .leading, spacing: 14) {
                PDFFileHeader(url: url, detail: pageCount.map { $0 == 1 ? "1 page" : "\($0) pages" } ?? " ")

                Label("Adds text fields, checkboxes and signature fields where the form has blanks. Saves a copy.", systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isScanned {
                    Label(MakeFillable.scannedNote, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if hasFields {
                    Label(MakeFillable.alreadyFillableNote, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if !isModelCached {
                        Label(MakeFillable.modelDownloadNote, systemImage: "arrow.down.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .task {
            let url = url
            let (pages, scanned, fields) = await Task.detached(priority: .userInitiated) {
                guard let document = PDFDocument(url: url) else { return (0, false, false) }
                return (document.pageCount, MakeFillable.hasScannedPages(document), MakeFillable.fieldCount(document) > 0)
            }.value
            pageCount = pages
            isScanned = scanned
            hasFields = fields
        }
        .onDisappear { run?.cancel() }
    }

    private func makeFillable() {
        isWorking = true
        let url = url
        run = Task {
            do {
                let saved = try await MakeFillable.make(url)
                isWorking = false
                actions.finished(SaveOutcome(saved: saved.map { [$0] } ?? [], unchanged: saved == nil ? 1 : 0, unchangedLabel: "no fields found"))
            } catch is CancellationError {
                isWorking = false
            } catch {
                isWorking = false
                isModelCached = MakeFillable.isModelCached()
                actions.failed(error)
            }
        }
    }
}
