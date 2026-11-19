import Foundation
import Testing
@testable import OpenShelf

/// Move and Copy open their picker on the folder they last put files in.
@MainActor
struct MoveCopyFolderTests {
    static func scratch() -> (UserDefaults, URL) {
        let name = "OpenShelfTests.lastFolder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (defaults, folder)
    }

    @Test func opensOnTheLastFolderUsedWhileItIsThere() throws {
        let (defaults, base) = Self.scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("here/report.pdf")
        let target = base.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        // Nothing remembered: where the file is.
        #expect(FileActions.startingFolder(for: [file], defaults: defaults)?.path == file.deletingLastPathComponent().path)
        // A move or copy that put nothing there (cancelled conflicts, all failed) is not remembered.
        FileActions.rememberFolder(target, afterDoing: 0, defaults: defaults)
        #expect(FileActions.startingFolder(for: [file], defaults: defaults)?.path == file.deletingLastPathComponent().path)
        // One that did is.
        FileActions.rememberFolder(target, afterDoing: 1, defaults: defaults)
        #expect(FileActions.startingFolder(for: [file], defaults: defaults)?.path == target.path)
        // Gone (deleted, or its disk not mounted): back to where the file is.
        try FileManager.default.removeItem(at: target)
        #expect(FileActions.startingFolder(for: [file], defaults: defaults)?.path == file.deletingLastPathComponent().path)
        // A file now sits where the folder was: not a folder, so not used.
        try Data().write(to: target)
        #expect(FileActions.startingFolder(for: [file], defaults: defaults)?.path == file.deletingLastPathComponent().path)
    }
}
