import AppKit
import SeasonKit
import SwiftUI

/// A menu bar app: no Dock icon, no main window, just weather on your desktop.
/// (`LSUIElement` is set in the build settings.)
@main
struct SeasonMyMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.settings.season.symbolName)
                .accessibilityLabel("SeasonMyMac")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
