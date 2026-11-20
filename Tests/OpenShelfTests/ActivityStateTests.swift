import Testing
@testable import OpenShelf

/// What makes OpenShelf "in use" for the install script (2026-11-20).
@MainActor
struct ActivityStateTests {
    typealias W = ActivityState.WindowInfo

    @Test func shelvesTabsAndToastsAreNotUse() {
        let idle = [W(className: "ShelfPanel", isPassive: true, isVisible: true),
                    W(className: "NSPanel", isPassive: true, isVisible: true),
                    W(className: "NSStatusBarWindow", isPassive: false, isVisible: true),
                    W(className: "EditorPanel", isPassive: false, isVisible: false)]
        #expect(ActivityState.busyReasons(windows: idle, conversions: 0).isEmpty)
    }

    @Test func openWindowsAndConversionsAreUse() {
        #expect(ActivityState.busyReasons(windows: [W(className: "EditorPanel", isPassive: false, isVisible: true)], conversions: 0) == ["EditorPanel"])
        #expect(ActivityState.busyReasons(windows: [W(className: "WheelPanel", isPassive: false, isVisible: true)], conversions: 0) == ["WheelPanel"])
        #expect(ActivityState.busyReasons(windows: [], conversions: 2) == ["2 conversion batches running"])
    }

    /// The shelf, edge tab and toast panels are marked passive where they are made.
    @Test func theShelfPanelIsPassive() {
        #expect(ShelfPanel(size: .init(width: 10, height: 10)).identifier == ActivityState.passive)
    }
}
