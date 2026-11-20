import Foundation
import Testing
@testable import OpenShelf

/// Audio tags (ROADMAP F5): the rules as pure functions, then a real round trip through
/// ffmpeg and ffprobe when they're installed.
struct AudioTagsTests {
    @Test func readsTagsInAnyCaseAndUnderTheirOtherNames() {
        let fields = AudioTags.fields(from: [
            "TITLE": "Song", "Artist": "Band", "album_artist": "Various", "TRACK": "3/12",
            "date": "2019-05-01", "DISCNUMBER": "1", "genre": "Jazz", "description": "nice",
        ])
        #expect(fields[.title] == "Song")
        #expect(fields[.artist] == "Band")
        #expect(fields[.albumArtist] == "Various")
        #expect(fields[.track] == "3/12")
        #expect(fields[.year] == "2019")
        #expect(fields[.disc] == "1")
        #expect(fields[.comment] == "nice")
        #expect(fields[.album] == nil)
    }

    @Test func severalFilesShareWhatTheyAgreeOn() {
        let (fields, mixed) = AudioTags.shared([
            [.album: "Blue", .artist: "A", .title: "One"],
            [.album: "Blue", .artist: "B", .title: "Two"],
        ])
        #expect(fields[.album] == "Blue")
        #expect(mixed == [.artist, .title])
        #expect(fields[.artist] == nil)
        // A field one file lacks and another has is mixed too.
        #expect(AudioTags.shared([[.genre: "Jazz"], [:]]).mixed == [.genre])
    }

    /// Only what changed is written; an emptied field clears its tag.
    @Test func writesOnlyWhatChanged() {
        let original: AudioTags.Fields = [.title: "Old", .artist: "Band"]
        #expect(AudioTags.changes(from: original, to: [.title: "New", .artist: "Band"]) == [.title: "New"])
        #expect(AudioTags.changes(from: original, to: [.title: "Old", .artist: ""]) == [.artist: ""])
        #expect(AudioTags.changes(from: original, to: original).isEmpty)
    }

    @Test func copiesTheSoundAndWritesTheChanges() {
        let input = URL(fileURLWithPath: "/m/song.mp3")
        let keep = AudioTags.arguments(input: input, changes: [.title: "A", .year: "2020"], cover: .keep, pathExtension: "MP3")
        #expect(keep == ["-i", "/m/song.mp3", "-map", "0", "-map_metadata", "0", "-c", "copy",
                         "-metadata", "title=A", "-metadata", "date=2020", "-id3v2_version", "3"])
        let removed = AudioTags.arguments(input: input, changes: [:], cover: .remove, pathExtension: "flac")
        #expect(removed == ["-i", "/m/song.mp3", "-map", "0:a", "-map_metadata", "0", "-c", "copy"])
        let replaced = AudioTags.arguments(input: input, changes: [.albumArtist: "V"], cover: .replace(URL(fileURLWithPath: "/m/c.jpg")), pathExtension: "m4a")
        #expect(replaced == ["-i", "/m/song.mp3", "-i", "/m/c.jpg", "-map", "0:a", "-map", "1:v", "-map_metadata", "0", "-c", "copy",
                             "-disposition:v:0", "attached_pic", "-metadata", "album_artist=V"])
    }

    static let ffmpeg = ExternalTools.detect().ffmpeg

    /// A short silent file in `format`, tagged, read back; the original is left alone
    /// unless the change is made in place.
    @Test(.enabled(if: ffmpeg != nil), arguments: [("mp3", "libmp3lame"), ("m4a", "aac"), ("flac", "flac")])
    func roundTrip(format: String, codec: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("song.\(format)")
        try await ProcessRunner.run(Self.ffmpeg!, ["-v", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "0.3", "-c:a", codec, "-metadata", "title=Old", "-metadata", "artist=Band", file.path])

        let copy = try await AudioTags.write(file, changes: [.title: "New", .album: "Blue", .year: "2021"], cover: .keep, inPlace: false)
        #expect(copy != file)
        let tagged = try await AudioTags.read(copy)
        #expect(tagged[.title] == "New")
        #expect(tagged[.artist] == "Band")
        #expect(tagged[.album] == "Blue")
        #expect(tagged[.year] == "2021")
        #expect(try await AudioTags.read(file)[.title] == "Old")

        _ = try await AudioTags.write(file, changes: [.artist: ""], cover: .keep, inPlace: true)
        let changed = try await AudioTags.read(file)
        #expect(changed[.title] == "Old")
        #expect((changed[.artist] ?? "").isEmpty)
    }
}
