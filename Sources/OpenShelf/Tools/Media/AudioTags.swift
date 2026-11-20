import Foundation

/// Audio tags (ROADMAP F5, David: "editing the metadata tags of files like mp3s"): read
/// with ffprobe, written with ffmpeg as a stream copy, so the sound is never re-encoded.
enum AudioTags {
    enum Key: String, CaseIterable, Sendable {
        case title, artist, album, albumArtist, track, disc, year, genre, comment

        var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .albumArtist: "Album Artist"
            case .track: "Track"
            case .disc: "Disc"
            case .year: "Year"
            case .genre: "Genre"
            case .comment: "Comment"
            }
        }

        /// The name ffmpeg writes (it maps these to ID3, MP4 atoms, Vorbis comments).
        var ffmpegName: String {
            switch self {
            case .albumArtist: "album_artist"
            case .year: "date"
            default: rawValue
            }
        }

        /// The names a file's tags may use for it, lowercased.
        var readNames: [String] {
            switch self {
            case .albumArtist: ["album_artist", "album artist", "albumartist"]
            case .year: ["date", "year", "tdrc", "tyer"]
            case .track: ["track", "tracknumber"]
            case .disc: ["disc", "discnumber"]
            case .comment: ["comment", "description"]
            default: [rawValue]
            }
        }
    }

    typealias Fields = [Key: String]

    /// The fields in ffprobe's format tags (any case).
    static func fields(from tags: [String: String]) -> Fields {
        let lower = Dictionary(tags.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        var fields: Fields = [:]
        for key in Key.allCases {
            guard let value = key.readNames.lazy.compactMap({ lower[$0] }).first else { continue }
            fields[key] = key == .year ? String(value.prefix(4)) : value
        }
        return fields
    }

    /// For several files: each field's value when every file has the same, and which
    /// fields differ ("mixed", left alone unless typed over).
    static func shared(_ all: [Fields]) -> (fields: Fields, mixed: Set<Key>) {
        var fields: Fields = [:]
        var mixed: Set<Key> = []
        for key in Key.allCases {
            let values = Set(all.map { $0[key] ?? "" })
            if values.count == 1 { fields[key] = values.first.flatMap { $0.isEmpty ? nil : $0 } } else { mixed.insert(key) }
        }
        return (fields, mixed)
    }

    /// The fields to write: those whose value differs from the file's. An emptied field
    /// clears the tag.
    static func changes(from original: Fields, to edited: Fields) -> Fields {
        var changes: Fields = [:]
        for key in Key.allCases where (edited[key] ?? "") != (original[key] ?? "") {
            changes[key] = edited[key] ?? ""
        }
        return changes
    }

    enum Cover: Equatable, Sendable {
        case keep
        case remove
        case replace(URL)
    }

    /// ffmpeg's arguments for `input` (everything before the output file): the audio and
    /// existing tags copied as they are, `changes` written over them, and the cover kept,
    /// removed or replaced.
    static func arguments(input: URL, changes: Fields, cover: Cover, pathExtension: String) -> [String] {
        var arguments = ["-i", input.path]
        if case .replace(let image) = cover { arguments += ["-i", image.path] }
        switch cover {
        case .keep: arguments += ["-map", "0"]
        case .remove: arguments += ["-map", "0:a"]
        case .replace: arguments += ["-map", "0:a", "-map", "1:v"]
        }
        arguments += ["-map_metadata", "0", "-c", "copy"]
        if case .replace = cover { arguments += ["-disposition:v:0", "attached_pic"] }
        for key in Key.allCases {
            if let value = changes[key] { arguments += ["-metadata", "\(key.ffmpegName)=\(value)"] }
        }
        // ID3 v2.3 reads everywhere (Finder, Music, most players); v2.4 not always.
        if pathExtension.lowercased() == "mp3" { arguments += ["-id3v2_version", "3"] }
        return arguments
    }

    /// The tags of `url`, as ffprobe reports them.
    static func read(_ url: URL, tools: ExternalTools = .current) async throws -> Fields {
        guard let ffprobe = tools.ffprobe else { throw MissingToolError(name: "ffprobe") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-tags-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        try await ProcessRunner.run(ffprobe, ["-v", "error", "-show_entries", "format_tags", "-of", "json", url.path], standardOutputFile: output)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
        let tags = ((json?["format"] as? [String: Any])?["tags"] as? [String: Any]) ?? [:]
        return fields(from: tags.compactMapValues { $0 as? String })
    }

    /// Writes `changes` and `cover` into a copy beside `url` ("… tagged"), or into `url`
    /// itself when `inPlace` (through a finished copy swapped in, so a failure leaves the
    /// original as it was). Returns the file written.
    static func write(_ url: URL, changes: Fields, cover: Cover, inPlace: Bool, tools: ExternalTools = .current) async throws -> URL {
        guard let ffmpeg = tools.ffmpeg else { throw MissingToolError(name: "ffmpeg") }
        let copy = OutputNaming.destination(for: url, suffix: "tagged", pathExtension: url.pathExtension.lowercased())
        try SaveError.checkWritable(copy)
        try await FFmpegJob.export(ffmpeg, arguments(input: url, changes: changes, cover: cover, pathExtension: url.pathExtension), to: copy, duration: 0, progress: { _ in })
        guard inPlace else { return copy }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: copy)
        return url
    }
}
