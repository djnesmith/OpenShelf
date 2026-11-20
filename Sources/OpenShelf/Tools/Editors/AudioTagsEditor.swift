import AppKit
import SwiftUI

/// The audio "Tags" tool (ROADMAP F5): title, artist, album, album artist, track, disc,
/// year, genre, comment and cover art, for one file or several (a field the files
/// disagree on shows "Mixed" and is left alone unless typed over). Saved as a copy beside
/// each file unless "Change the original files" is on. The sound is copied as it is.
struct AudioTagsEditor: View {
    static let windowSize = CGSize(width: 470, height: 560)

    let urls: [URL]
    let actions: EditorActions

    @State private var originals: [AudioTags.Fields] = []
    @State private var mixed: Set<AudioTags.Key> = []
    @State private var edited: [AudioTags.Key: String] = [:]
    @State private var cover: AudioTags.Cover = .keep
    @State private var inPlace = false
    @State private var isLoading = true
    @State private var isWorking = false

    private var shared: AudioTags.Fields { AudioTags.shared(originals).fields }

    /// What each file gets: its own tags with only the fields typed into changed.
    private var plannedChanges: [AudioTags.Fields] {
        originals.map { original in
            var target = original
            for key in AudioTags.Key.allCases where edited[key] != nil { target[key] = edited[key] }
            return AudioTags.changes(from: original, to: target)
        }
    }

    private var canSave: Bool {
        !isLoading && !isWorking && (cover != .keep || plannedChanges.contains { !$0.isEmpty })
    }

    var body: some View {
        EditorChrome(
            title: "Audio Tags",
            primaryTitle: isWorking ? "Saving…" : "Save",
            isPrimaryEnabled: canSave,
            actions: actions,
            onReset: { edited = [:]; cover = .keep },
            onPrimary: save
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    ForEach(AudioTags.Key.allCases, id: \.self) { key in
                        EditorRow(label: key.label) {
                            TextField(mixed.contains(key) && edited[key] == nil ? "Mixed" : "", text: binding(for: key))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(key.label)
                        }
                    }
                    EditorRow(label: "Cover") {
                        Text(coverDescription).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Replace…", action: chooseCover)
                        Button("Remove") { cover = .remove }
                    }
                    Divider().padding(.vertical, 2)
                    Toggle("Change the original files", isOn: $inPlace)
                        .help("Off: each file is saved as a copy beside it, “… tagged”")
                }
                Spacer(minLength: 0)
            }
        }
        .task { await load() }
    }

    private var coverDescription: String {
        switch cover {
        case .keep: "Kept as it is"
        case .remove: "Removed when saved"
        case .replace(let url): "From \(url.lastPathComponent)"
        }
    }

    private func binding(for key: AudioTags.Key) -> Binding<String> {
        Binding(get: { edited[key] ?? shared[key] ?? "" }, set: { edited[key] = $0 })
    }

    private func load() async {
        var read: [AudioTags.Fields] = []
        for url in urls { read.append((try? await AudioTags.read(url)) ?? [:]) }
        originals = read
        mixed = AudioTags.shared(read).mixed
        isLoading = false
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cover = .replace(url)
    }

    private func save() {
        isWorking = true
        let jobs = Array(zip(urls, plannedChanges))
        let cover = cover
        let inPlace = inPlace
        Task {
            do {
                var saved: [URL] = []
                var unchanged = 0
                for (url, changes) in jobs {
                    if changes.isEmpty && cover == .keep {
                        unchanged += 1
                        continue
                    }
                    saved.append(try await AudioTags.write(url, changes: changes, cover: cover, inPlace: inPlace))
                }
                isWorking = false
                actions.finished(SaveOutcome(saved: saved, unchanged: unchanged, savedLabel: "tagged"))
            } catch {
                isWorking = false
                actions.failed(error)
            }
        }
    }
}
