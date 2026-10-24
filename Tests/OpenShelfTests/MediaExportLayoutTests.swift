import AppKit
import SwiftUI
import Testing
@testable import OpenShelf

/// The Export editor fits its window, so nothing is clipped at either edge.
@MainActor
struct MediaExportLayoutTests {
    let actions = EditorActions(close: {}, finished: { _ in }, failed: { _ in }, focus: {})
    let width = MediaExportEditor.windowSize.width

    func fittingWidth(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    /// How wide the view is when offered the window's width: wider means
    /// something in it can't shrink, and the window clips it.
    func widthInWindow(_ view: some View) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2000)).width
    }

    @Test func longNamesFit() {
        let name = "/tmp/TT 26 Setlist Rehearsal 102026 +1.5 Clean With A Much Longer Name Than Fits"
        for ext in ["mp3", "mp4"] {
            let editor = MediaExportEditor(urls: [URL(fileURLWithPath: "\(name).\(ext)")], actions: actions)
            #expect(widthInWindow(editor) <= width, "\(ext)")
        }
    }

    /// Offered less room than its segments need, the picker turns into a
    /// menu rather than pushing past the edge.
    @Test func aNarrowWindowGetsAMenu() {
        let picker = FittingPicker(
            title: "Format", selection: .constant(AudioExportFormat.aac), options: AudioExportFormat.allCases, label: \.title
        )
        #expect(NSHostingController(rootView: picker).sizeThatFits(in: CGSize(width: 200, height: 100)).width <= 200)
    }

    /// Every format and every container's codecs fit as segments, as the
    /// editor lays them out (16 pt margins each side).
    @Test func everyFormatAndCodecRowFits() {
        func rowWidth<Option: Hashable & Identifiable>(
            _ label: String, _ options: [Option], _ title: @escaping (Option) -> String
        ) -> CGFloat {
            fittingWidth(
                EditorRow(label: label) {
                    FittingPicker(title: label, selection: .constant(options[0]), options: options, label: title)
                }
                .padding(.horizontal, 16)
            )
        }
        #expect(rowWidth("Format", AudioExportFormat.allCases, \.title) <= width)
        for container in VideoContainer.allCases {
            #expect(rowWidth("Video", container.codecs, \.title) <= width, "\(container)")
        }
    }
}
