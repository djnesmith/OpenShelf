import SwiftUI

@main
struct OpenShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Mail's single keys (MAIL-PLAN slice E): off until turned on here.
    @AppStorage(MailKeyTap.enabledKey) private var mailSingleKeys = false

    var body: some Scene {
        MenuBarExtra {
            Button("New Shelf") { appDelegate.shelves.newShelf() }
                .keyboardShortcut("n")
            Button(appDelegate.shelves.areHidden ? "Show Shelves" : "Hide Shelves") { appDelegate.shelves.toggleHidden() }
                .disabled(!appDelegate.shelves.hasShelves)
            Button("Close All Shelves") { appDelegate.shelves.closeAll() }
                .disabled(!appDelegate.shelves.hasShelves)
            if appDelegate.shelves.hasShelves {
                Section("Open Shelves") {
                    ForEach(appDelegate.shelves.openShelves) { shelf in
                        Button(shelf.summary) { appDelegate.shelves.show(shelf) }
                    }
                }
            }
            Divider()
            openWheelButton
            Toggle("Mail Single Keys", isOn: $mailSingleKeys)
                .onChange(of: mailSingleKeys) { MailKeyTap.shared.update(front: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) }
            Button("Check Mail (read only)") { MailHelpers.writeCheck() }
            Button("Take the Tour…") { TourWindowController.present() }
            Button("Settings…") { SettingsWindowController.shared.show() }
                .keyboardShortcut(",")
            Button("About OpenShelf") { AboutPanel.show() }
            Divider()
            Button("Quit OpenShelf") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    /// Shows the global shortcut next to the item when it can be expressed.
    @ViewBuilder private var openWheelButton: some View {
        let button = Button("Open Wheel for Selection") { appDelegate.openWheelForSelection() }
        if let combo = Preferences.shared.openWheelShortcut, let key = combo.keyEquivalent {
            button.keyboardShortcut(key, modifiers: combo.eventModifiers)
        } else {
            button
        }
    }
}
