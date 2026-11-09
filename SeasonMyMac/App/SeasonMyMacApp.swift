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
            MenuBarLabel(model: appDelegate.model)
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
        #if DEBUG
            UIGallery.showIfRequested(model: model)
        #endif
    }
}

/// The menu bar item: the app's icon, or the Christmas countdown instead.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.isPlayModeOn {
            Image(systemName: "hand.raised.fill")
                .accessibilityLabel("SeasonMyMac, Snow Play")
        } else if model.settings.extras.countdownInMenuBar {
            Text(countdown)
                .accessibilityLabel(Text("SeasonMyMac, \(countdown)"))
        } else {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("SeasonMyMac")
        }
    }

    private var countdown: String {
        let days = model.daysUntilChristmas
        let isShort = model.settings.extras.countdownStyle == .short
        switch days {
        case 0: return String(localized: "Merry Christmas")
        case 1: return String(localized: "Christmas Eve")
        default:
            return isShort ? String(localized: "\(days) days") : String(localized: "\(days) days until Christmas")
        }
    }
}

/// The app's icon, sized for the menu bar.
private enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let source = NSApplication.shared.applicationIconImage!
        let image = NSImage(size: size, flipped: false) { rect in
            // App icons have transparent margins; draw it a little larger so it fills the space.
            source.draw(in: rect.insetBy(dx: -1, dy: -1), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }()
}
