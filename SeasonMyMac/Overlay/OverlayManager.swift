import AppKit
import OSLog

/// Owns one overlay per screen and keeps them in step with the system:
/// displays being added or removed, the Mac sleeping, and Low Power Mode.
final class OverlayManager: NSObject {
    let desktop = DesktopScanner()

    private(set) var settings: AppSettings
    private let metal = MetalContext()
    private var overlays: [OverlayWindow] = []
    /// The displays are asleep or another user is logged in.
    private var isSuspended = false

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        observeSystemEvents()
    }

    /// Applies new settings, rebuilding the overlays only when that's needed.
    func apply(_ newSettings: AppSettings) {
        let previous = settings
        settings = newSettings
        desktop.appRules = Dictionary(
            newSettings.visibility.appRules.map { ($0.bundleIdentifier, $0.behavior) },
            uniquingKeysWith: { first, _ in first }
        )

        let needsRebuild =
            previous.hasVisibleEffects != newSettings.hasVisibleEffects
            || previous.visibility.displays != newSettings.visibility.displays
            || overlays.isEmpty
        if needsRebuild {
            rebuildOverlays()
        } else {
            for overlay in overlays {
                overlay.seasonView.settings = newSettings
                overlay.setShowsOverFullScreenApps(!newSettings.visibility.hidesInFullScreen)
            }
        }
    }

    func shakeOffAllSnow() {
        for overlay in overlays {
            overlay.seasonView.shakeOffAllSnow()
        }
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        for overlay in overlays {
            overlay.seasonView.stop()
            overlay.orderOut(nil)
        }
        overlays.removeAll()

        guard settings.hasVisibleEffects, !isSuspended else { return }
        guard let metal else {
            Logger.app.error("Can't draw anything without Metal")
            return
        }

        let screens = settings.visibility.displays == .main ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for screen in screens {
            let view = SeasonView(screen: screen, metal: metal, desktop: desktop, settings: settings)
            view.isLowPowerModeEnabled = lowPower
            let window = OverlayWindow(
                screen: screen,
                seasonView: view,
                showsOverFullScreenApps: !settings.visibility.hidesInFullScreen
            )
            window.orderFrontRegardless()
            view.start()
            overlays.append(window)
        }
    }

    // MARK: System events

    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange, object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
    }

    @objc private func screensDidChange() {
        rebuildOverlays()
    }

    @objc private func suspend() {
        isSuspended = true
        rebuildOverlays()
    }

    @objc private func resume() {
        isSuspended = false
        rebuildOverlays()
    }

    /// Posted on an arbitrary thread, so hop to the main actor.
    @objc nonisolated private func powerStateDidChange() {
        Task { @MainActor in
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            for overlay in self.overlays {
                overlay.seasonView.isLowPowerModeEnabled = lowPower
            }
        }
    }
}
