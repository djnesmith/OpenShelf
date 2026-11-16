import Foundation

/// The tempo of audio files, from `aubio tempo`. It never changes the file.
enum BPM {
    enum Outcome: Equatable, Sendable {
        /// aubio prints "(uncertain)" when it heard fewer than 10 beats.
        case bpm(Int, uncertain: Bool)
        case noBeat
        case failed(String)
    }

    struct Result: Equatable, Sendable {
        let file: URL
        let outcome: Outcome
    }

    /// What Homebrew's aubio reads (it has no FLAC or OGG reader).
    static let extensions: Set<String> = ["wav", "mp3", "m4a", "aif", "aiff", "caf", "aac", "opus"]

    static func reads(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func detect(_ files: [URL], tools: ExternalTools = .current, runner: ToolRunner = ProcessRunner.live) async throws -> [Result] {
        var results: [Result] = []
        for file in files {
            results.append(try await detect(file, tools: tools, runner: runner))
        }
        return results
    }

    static func detect(_ file: URL, tools: ExternalTools = .current, runner: ToolRunner = ProcessRunner.live) async throws -> Result {
        guard let aubio = tools.aubio else { throw MissingToolError(name: "aubio") }
        let lines = Lines()
        do {
            try await runner(ToolInvocation(executable: aubio, arguments: ["tempo", file.path])) { lines.append($0) }
        } catch let failure as ProcessFailure {
            return Result(file: file, outcome: .failed(reason(failure, file: file)))
        }
        // No usable line (aubio printed "inf bpm" or nothing) means it read the file but found no tempo.
        return Result(file: file, outcome: lines.all.compactMap(parse).last ?? .noBeat)
    }

    /// aubio's own reason, "source_wavread: Failed opening x.wav (could not find RIFF header)",
    /// from its "AUBIO ERROR: " line, which Python's traceback may follow with
    /// a vaguer last line; otherwise that last line.
    static func reason(_ failure: ProcessFailure, file: URL) -> String {
        let aubioLine = failure.errorOutput.split(whereSeparator: \.isNewline).last { $0.contains("AUBIO ERROR: ") }
        let line = aubioLine.map { String($0.components(separatedBy: "AUBIO ERROR: ").last ?? "") } ?? failure.message
        let shown = line.replacingOccurrences(of: file.path, with: file.lastPathComponent).trimmingCharacters(in: .whitespaces)
        return shown.isEmpty ? "aubio failed" : shown
    }

    /// aubio's last line: "146.44 bpm", "146.44 bpm (uncertain)" or "unknown bpm".
    static func parse(_ line: String) -> Outcome? {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line == "unknown bpm" { return .noBeat }
        let uncertain = line.hasSuffix(" bpm (uncertain)")
        guard uncertain || line.hasSuffix(" bpm"),
              let number = line.split(separator: " ").first.flatMap({ Double($0) }), number.isFinite
        else { return nil }
        return .bpm(Int(number.rounded()), uncertain: uncertain)
    }

    /// One line per file, in the order given.
    static func report(_ results: [Result]) -> String {
        results.map { result in
            let value = switch result.outcome {
            case let .bpm(bpm, uncertain): "\(bpm) BPM" + (uncertain ? " (uncertain, few beats)" : "")
            case .noBeat: "no steady beat found"
            case let .failed(message): "couldn’t read: \(message)"
            }
            return "\(result.file.lastPathComponent) — \(value)"
        }.joined(separator: "\n")
    }

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }
}
