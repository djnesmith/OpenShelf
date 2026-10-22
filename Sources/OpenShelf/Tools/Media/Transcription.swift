@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

enum TranscriptionError: LocalizedError, Equatable {
    case notAllowed
    case noRecognizer(String)
    case notOnDevice(String)
    case nothingHeard

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            "Allow OpenShelf in System Settings → Privacy & Security → Speech Recognition."
        case .noRecognizer(let language):
            "Speech recognition doesn’t support \(language)."
        case .notOnDevice(let language):
            "On-device recognition for \(language) isn’t available on this Mac, so nothing was sent anywhere. Turn on Dictation for that language in System Settings → Keyboard to download it."
        case .nothingHeard:
            "No speech was recognised."
        }
    }
}

/// Speech to text, always on this Mac: Apple's speech recogniser with
/// on-device recognition required, so audio never leaves the computer.
/// Writes "<name>.txt" and "<name>.srt" beside the file.
enum Transcription {
    /// A recognised word or phrase and when it's said, in seconds.
    struct Segment: Equatable, Sendable {
        var text: String
        var start: Double
        var duration: Double
        var end: Double { start + duration }
    }

    /// Audio is recognised in pieces of this many seconds.
    static let chunkLength: Double = 50

    static func transcribe(
        _ url: URL,
        locale: Locale = .current,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        try await authorize()
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.noRecognizer(language(locale))
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.notOnDevice(language(locale))
        }
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw MediaToolError.noTracks(url) }
        let duration = try await asset.load(.duration).seconds

        var segments: [Segment] = []
        let chunks = chunkStarts(duration: duration)
        for (index, start) in chunks.enumerated() {
            try Task.checkCancellation()
            let piece = try await exportAudio(asset, from: start, length: min(chunkLength, duration - start))
            defer { try? FileManager.default.removeItem(at: piece) }
            segments += try await recognize(piece, with: recognizer).map { Segment(text: $0.text, start: $0.start + start, duration: $0.duration) }
            progress(Double(index + 1) / Double(chunks.count))
        }
        guard !segments.isEmpty else { throw TranscriptionError.nothingHeard }

        let text = OutputNaming.destination(for: url, pathExtension: "txt")
        try SaveError.checkWritable(text)
        try plainText(segments).write(to: text, atomically: true, encoding: .utf8)
        let subtitles = OutputNaming.destination(for: url, pathExtension: "srt")
        try srt(cues(segments)).write(to: subtitles, atomically: true, encoding: .utf8)
        return [text, subtitles]
    }

    // MARK: Pieces

    /// Where each piece starts.
    static func chunkStarts(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        return stride(from: 0, to: duration, by: chunkLength).map { $0 }
    }

    private static func authorize() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw TranscriptionError.notAllowed }
    }

    private static func language(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// `length` seconds of `asset`'s sound from `start`, as a temporary M4A.
    private static func exportAudio(_ asset: AVURLAsset, from start: Double, length: Double) async throws -> URL {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-speech-\(UUID().uuidString).m4a")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaToolError.cannotExport("as sound for recognition")
        }
        session.timeRange = CMTimeRange(start: MediaTime.cmTime(start), duration: MediaTime.cmTime(length))
        try await session.export(to: output, as: .m4a)
        return output
    }

    private static func recognize(_ url: URL, with recognizer: SFSpeechRecognizer) async throws -> [Segment] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let once = ResumeOnce()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Segment], Error>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        let segments = result.bestTranscription.segments.map {
                            Segment(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                        }
                        if once.claim() { continuation.resume(returning: segments) }
                    } else if let error {
                        // A silent piece ends with "no speech detected"; that's an empty piece.
                        if once.claim() {
                            (error as NSError).code == 1110 ? continuation.resume(returning: []) : continuation.resume(throwing: error)
                        }
                    }
                }
                once.task = task
            }
        } onCancel: {
            once.task?.cancel()
        }
    }

    // MARK: Writing

    /// The words as running text, a paragraph where the speaker pauses for
    /// more than two seconds.
    static func plainText(_ segments: [Segment]) -> String {
        var text = ""
        var previous: Segment?
        for segment in segments {
            if let previous {
                text += segment.start - previous.end > 2 ? "\n\n" : " "
            }
            text += segment.text
            previous = segment
        }
        return text + "\n"
    }

    /// Words grouped into subtitles: a new one after a sentence ends, a pause
    /// of a second, eight words, or five seconds.
    static func cues(_ segments: [Segment]) -> [Segment] {
        var cues: [Segment] = []
        var words: [Segment] = []
        func flush() {
            guard let first = words.first, let last = words.last else { return }
            cues.append(Segment(text: words.map(\.text).joined(separator: " "), start: first.start, duration: last.end - first.start))
            words = []
        }
        for segment in segments {
            if let first = words.first, let last = words.last,
               segment.start - last.end > 1 || words.count >= 8 || segment.end - first.start > 5
                || last.text.last.map(".?!".contains) == true {
                flush()
            }
            words.append(segment)
        }
        flush()
        return cues
    }

    static func srt(_ cues: [Segment]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(srtTime(cue.start)) --> \(srtTime(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// "01:02:03,450".
    static func srtTime(_ seconds: Double) -> String {
        let milliseconds = Int((max(seconds, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
    }
}

/// Resumes a continuation once, though the recogniser may call back again.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    var task: SFSpeechRecognitionTask?

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
