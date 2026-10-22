import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// How many times an animated GIF plays.
enum GIFPlays: Hashable, CaseIterable, Identifiable {
    case forever, once, twice, threeTimes, fiveTimes

    var id: Self { self }

    var title: String {
        switch self {
        case .forever: "Forever"
        case .once: "Once"
        case .twice: "2×"
        case .threeTimes: "3×"
        case .fiveTimes: "5×"
        }
    }

    /// ImageIO's loop count: how many times it plays in all, 0 for forever.
    /// It writes the GIF's repeat count (one fewer) itself, and no loop block for 1.
    var loopCount: Int {
        switch self {
        case .forever: 0
        case .once: 1
        case .twice: 2
        case .threeTimes: 3
        case .fiveTimes: 5
        }
    }

    /// For the file name: "Loop Forever", "Plays Once", "Plays 3×".
    var suffix: String {
        self == .forever ? "Loop Forever" : "Plays \(title)"
    }
}

enum GIFLoop {
    /// A copy of `url` with every frame and its timing kept, playing `plays` times.
    static func save(_ url: URL, plays: GIFPlays) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.unreadable(url)
        }
        let count = CGImageSourceGetCount(source)
        let destinationURL = OutputNaming.destination(for: url, suffix: plays.suffix, pathExtension: "gif")
        try SaveError.checkWritable(destinationURL)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw SaveError.diagnose(destinationURL)
        }
        let gif: [CFString: Any] = [kCGImagePropertyGIFLoopCount: plays.loopCount]
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)
        for index in 0..<count {
            CGImageDestinationAddImageFromSource(destination, source, index, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw SaveError.diagnose(destinationURL)
        }
        return destinationURL
    }

    /// How many times `url` plays, as ImageIO reads it: 0 for forever, 1 without a loop block.
    static func loopCount(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return nil }
        return gif[kCGImagePropertyGIFLoopCount] as? Int
    }
}

/// Sets how many times animated GIFs play.
struct GIFLoopEditor: View {
    static let windowSize = CGSize(width: 420, height: 210)

    let urls: [URL]
    let actions: EditorActions
    @State private var plays = GIFPlays.forever

    var body: some View {
        EditorChrome(
            title: "Loop",
            primaryTitle: "Save",
            actions: actions,
            onPrimary: save
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) GIFs")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Plays") {
                    Picker("Plays", selection: $plays) {
                        ForEach(GIFPlays.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func save() {
        do {
            actions.saved(try urls.map { try GIFLoop.save($0, plays: plays) })
        } catch {
            actions.failed(error)
        }
    }
}
