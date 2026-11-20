import Foundation

/// Where OpenShelf writes its logs and state. Under tests they go to a folder of their own
/// in the temporary directory, never David's real ones (2026-11-20: a test wrote "test"
/// lines into ~/Library/Logs/OpenShelf/mail-scripts.log).
enum OpenShelfFiles {
    /// Whether this process is a test run (xctest, or SwiftPM's testing helper).
    static let isTesting: Bool = {
        let info = ProcessInfo.processInfo
        return info.processName == "xctest" || info.processName.contains("swiftpm-testing-helper")
            || info.environment["XCTestConfigurationFilePath"] != nil
            || info.arguments.contains { $0.hasSuffix(".xctest") || $0.contains(".xctest/") }
    }()

    static var logs: URL {
        isTesting
            ? FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelfTests/Logs", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenShelf", isDirectory: true)
    }

    static var support: URL {
        isTesting
            ? FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelfTests/Support", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenShelf", isDirectory: true)
    }
}
