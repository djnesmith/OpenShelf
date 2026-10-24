import CoreGraphics
import Foundation
import Observation

/// What the media editors share when given several files: a picture for each
/// file's place in the filmstrip, and exporting the files one after another.
enum MediaBatch {
    /// A small frame of a video for a filmstrip; nil for sound files and files
    /// that can't be read.
    static func thumbnail(of url: URL) async -> CGImage? {
        guard let basics = try? await MediaLoading.basics(of: url), basics.hasVideo else { return nil }
        return try? await MediaLoading.poster(of: url, maximumSize: 160)
    }

    /// How far through `count` exports the whole batch is when the one at
    /// `index` is `fraction` done: halfway through the second of four is 0.375.
    static func overall(_ fraction: Double, index: Int, count: Int) -> Double {
        guard count > 0 else { return 1 }
        return (Double(index) + min(max(fraction, 0), 1)) / Double(count)
    }

    /// Runs `export` for each of `count` files in turn, adding what each
    /// writes to `outcome`. Stops at the first error. `sources[index]` is the
    /// file job `index` edits, so the toast can say when its format changed
    /// (see `KeepFormat`).
    static func run(
        _ count: Int,
        sources: [URL] = [],
        into outcome: SaveOutcome,
        progress: @escaping @Sendable (_ fraction: Double, _ index: Int) -> Void,
        export: (_ index: Int, _ progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
    ) async throws -> SaveOutcome {
        var outcome = outcome
        for index in 0..<count {
            try Task.checkCancellation()
            progress(overall(0, index: index, count: count), index)
            let written = try await export(index) { fraction in
                progress(overall(fraction, index: index, count: count), index)
            }
            if outcome.detail == nil, sources.indices.contains(index), let output = written.first {
                outcome.detail = KeepFormat.note(source: sources[index], output: output)
            }
            outcome.saved += written
        }
        return outcome
    }
}

/// An editor's export of several files: its progress while it runs, then the
/// saved files and how many were left alone.
@MainActor
@Observable
final class MediaBatchExport {
    private(set) var progress: Double?
    private(set) var detail: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Exports `count` files with `export`; `outcome` already counts the
    /// files left alone and names what happened to the rest.
    func start(
        _ count: Int,
        sources: [URL] = [],
        outcome: SaveOutcome,
        actions: EditorActions,
        export: @escaping @Sendable (_ index: Int, _ progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
    ) {
        progress = 0
        task = Task { [weak self] in
            do {
                let result = try await MediaBatch.run(count, sources: sources, into: outcome, progress: { fraction, index in
                    Task { @MainActor in
                        // Late reports mustn't bring back a finished progress bar.
                        guard self?.progress != nil else { return }
                        self?.progress = fraction
                        self?.detail = count > 1 ? "Exporting \(index + 1) of \(count)…" : nil
                    }
                }, export: export)
                self?.finish()
                actions.finished(result)
            } catch is CancellationError {
                self?.finish()
            } catch {
                self?.finish()
                actions.failed(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func finish() {
        progress = nil
        detail = nil
    }
}
