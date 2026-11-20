import AppKit

/// Whether OpenShelf is in use, for the install script: it relaunches the app only when
/// nothing is open and nothing has been typed or clicked for a while (2026-11-20: an
/// install closed David's Edit window). Written to
/// ~/Library/Application Support/OpenShelf/state.json every few seconds; no content.
@MainActor
final class ActivityState {
    static let shared = ActivityState()
    /// Windows that are always there or only report: shelves, the edge tab, toasts.
    static let passive = NSUserInterfaceItemIdentifier("openshelf.passive")

    private var lastInput = Date()
    private var monitor: Any?
    private var timer: Timer?

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenShelf/state.json")
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
            self?.lastInput = Date()
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { ActivityState.shared.write() }
        }
        write()
    }

    /// A window as the busy check sees it.
    struct WindowInfo: Equatable {
        var className: String
        var isPassive: Bool
        var isVisible: Bool
    }

    /// Why OpenShelf is busy, or empty when it isn't: any visible window that isn't a
    /// shelf, the edge tab or a toast (the Edit window, a wheel, a prompt or picker, a tool
    /// window, Settings, an open menu), and conversions still running.
    static func busyReasons(windows: [WindowInfo], conversions: Int) -> [String] {
        var reasons = windows.filter { $0.isVisible && !$0.isPassive && !$0.className.contains("StatusBarWindow") }.map(\.className)
        if conversions > 0 { reasons.append("\(conversions) conversion batch\(conversions == 1 ? "" : "es") running") }
        return reasons
    }

    func write(now: Date = .now) {
        let windows = NSApp.windows.map {
            WindowInfo(className: String(describing: type(of: $0)), isPassive: $0.identifier == Self.passive, isVisible: $0.isVisible)
        }
        let reasons = Self.busyReasons(windows: windows, conversions: ConversionRunner.shared.activeBatches)
        let formatter = ISO8601DateFormatter()
        let state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "busy": !reasons.isEmpty,
            "reasons": reasons,
            "lastInputAt": formatter.string(from: lastInput),
            "updatedAt": formatter.string(from: now),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
