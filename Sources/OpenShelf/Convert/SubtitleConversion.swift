import Foundation

/// SubRip (SRT) and WebVTT subtitles: convert between them or strip to plain
/// text. With ffmpeg, also Advanced SubStation Alpha (ASS), SubStation Alpha
/// (SSA) and TTML, in and out.
enum SubtitleConversion {
    /// What only ffmpeg reads or writes.
    static let ffmpegFormats: [OutputFormat] = [.ass, .ssa, .ttml]
    static let ffmpegExtensions: Set<String> = ["ass", "ssa"]

    static func formats(for url: URL, tools: ExternalTools) -> [OutputFormat] {
        let extras = tools.ffmpeg != nil ? ffmpegFormats : []
        if ffmpegExtensions.contains(url.pathExtension.lowercased()) {
            return tools.ffmpeg != nil ? [.srt, .vtt, .txt] + extras : []
        }
        return [.txt, .srt, .vtt] + extras
    }

    static func convert(_ source: URL, to format: OutputFormat, tools: ExternalTools) async throws -> URL {
        let fromFFmpegFormat = ffmpegExtensions.contains(source.pathExtension.lowercased())
        guard fromFFmpegFormat || ffmpegFormats.contains(format) else { return try convert(source, to: format) }
        guard let ffmpeg = tools.ffmpeg else { throw MissingToolError(name: "ffmpeg") }
        guard format != .txt else {
            // Through SRT, which this file reads.
            let srt = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: srt) }
            try await FFmpegJob.run(ffmpeg, ffmpegArguments(source, to: .srt), output: srt, duration: 0) { _ in }
            guard let text = try? String(contentsOf: srt, encoding: .utf8) else { throw ConversionError.unreadable(source) }
            let destination = OutputNaming.destination(for: source, pathExtension: "txt")
            try plainText(parse(text)).write(to: destination, atomically: true, encoding: .utf8)
            return destination
        }
        guard let pathExtension = format.fileExtension else { throw ConversionError.unsupported("subtitles to \(format.title)") }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        try await FFmpegJob.export(ffmpeg, ffmpegArguments(source, to: format), to: destination, duration: 0) { _ in }
        return destination
    }

    static func ffmpegArguments(_ source: URL, to format: OutputFormat) -> [String] {
        let codec = switch format {
        case .vtt: "webvtt"
        case .srt: "srt"
        default: format.rawValue
        }
        // TTML needs its muxer named; the rest follow the file's extension.
        let muxer: [String] = format == .ttml ? ["-f", "ttml"] : []
        return ["-i", source.path, "-map", "0:s:0", "-c:s", codec] + muxer
    }

    struct Cue: Equatable {
        var start: String
        var end: String
        var lines: [String]
    }

    static func convert(_ source: URL, to format: OutputFormat) throws -> URL {
        guard let text = try? String(contentsOf: source, encoding: .utf8) else { throw ConversionError.unreadable(source) }
        let cues = parse(text)
        let output: String
        switch format {
        case .txt: output = plainText(cues)
        case .srt: output = srt(cues)
        case .vtt: output = vtt(cues)
        default: throw ConversionError.unsupported("subtitles to \(format.title)")
        }
        let destination = OutputNaming.destination(for: source, pathExtension: format.rawValue)
        try output.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// Reads cues from either format; headers, notes and style blocks are skipped.
    static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2 else { return nil }
            let start = parts[0].trimmingCharacters(in: .whitespaces)
            // VTT allows cue settings after the end time.
            let end = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            return Cue(start: start, end: end, lines: Array(lines[(timingIndex + 1)...]))
        }
    }

    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n\(cue.lines.joined(separator: "\n"))"
        }
        .joined(separator: "\n\n") + "\n"
    }

    static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.lines.joined(separator: "\n"))"
        }
        .joined(separator: "\n\n") + "\n"
    }

    /// Dialogue only: no numbers, timings, or formatting tags.
    static func plainText(_ cues: [Cue]) -> String {
        cues.flatMap(\.lines)
            .map { $0.replacingOccurrences(of: "<[^>]+>|\\{[^}]+\\}", with: "", options: .regularExpression) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n") + "\n"
    }

    /// Normalises "1:02.5" or "00:01:02,500" to "00:01:02<sep>500".
    static func timestamp(_ value: String, separator: String) -> String {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        var components = normalized.split(separator: ":").map(String.init)
        while components.count < 3 { components.insert("0", at: 0) }
        let secondsParts = components[2].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let hours = Int(components[0]) ?? 0
        let minutes = Int(components[1]) ?? 0
        let seconds = Int(secondsParts[0]) ?? 0
        let fraction = secondsParts.count > 1 ? secondsParts[1] : "0"
        let millis = Int(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, separator, millis)
    }
}
