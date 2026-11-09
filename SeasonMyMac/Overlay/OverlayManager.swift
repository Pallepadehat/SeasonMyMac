import AppKit
import OSLog

/// Owns one overlay per screen and keeps them in step with the system:
/// displays being added or removed, the Mac sleeping, and Low Power Mode.
/// Also runs the things that span screens: Snow Play, Santa's schedule and
/// listening for music.
final class OverlayManager: NSObject {
    let desktop = DesktopScanner()
    let music = MusicSync()

    private(set) var settings: AppSettings
    private let metal = MetalContext()
    private var overlays: [OverlayWindow] = []
    /// The displays are asleep or another user is logged in.
    private var isSuspended = false

    /// Called when Snow Play turns on or off (from a right-click or the timeout, too).
    var onPlayModeChange: ((Bool) -> Void)?

    /// Snow Play: the pointer grabs snow without holding any keys.
    private(set) var isPlayModeOn = false
    private let hud = PlayHUD()
    private var lastPlayTime = Date()
    private var playTimeout: Timer?
    private var escapeMonitors: [Any] = []

    private var sleighTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        hud.onDone = { [weak self] in self?.setPlayMode(false) }
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
        music.isEnabled = newSettings.lights.isEnabled && newSettings.lights.dancesToMusic

        let shownDisplays = Set(overlays.map(\.seasonView.display.id))
        let needsRebuild = overlays.isEmpty || shownDisplays != Set(displaysToShow().map(\.id))
        if needsRebuild {
            rebuildOverlays()
        } else {
            for overlay in overlays {
                overlay.seasonView.settings = newSettings.resolved(for: overlay.seasonView.display)
                overlay.setShowsOverFullScreenApps(!newSettings.visibility.hidesInFullScreen)
            }
        }
        if !newSettings.play.isEnabled || !newSettings.snow.isEnabled, isPlayModeOn {
            setPlayMode(false)
        }
        if previous.extras.sleigh != newSettings.extras.sleigh || previous.extras.sleighFrequency != newSettings.extras.sleighFrequency {
            scheduleSleigh()
        }
    }

    // MARK: Winter fun

    func shakeOffAllSnow() {
        for overlay in overlays {
            overlay.seasonView.shakeOffAllSnow()
        }
    }

    /// Drops a snowman on the screen with the pointer.
    func buildSnowman() {
        (overlayUnderPointer ?? overlays.first)?.seasonView.buildSnowman()
    }

    func clearSnowmen() {
        for overlay in overlays {
            overlay.seasonView.meltSnowmen()
        }
    }

    func letItSnow() {
        for overlay in overlays {
            overlay.seasonView.letItSnow()
        }
    }

    /// Sends Santa across the screen with the pointer, right now.
    func callSanta() {
        let candidates = overlays.filter(\.seasonView.canLaunchSleigh)
        let preferred = candidates.first { $0 === overlayUnderPointer } ?? candidates.first
        preferred?.seasonView.launchSleigh()
    }

    private var overlayUnderPointer: OverlayWindow? {
        let mouse = NSEvent.mouseLocation
        return overlays.first { $0.frame.contains(mouse) }
    }

    // MARK: Snow Play

    func setPlayMode(_ isOn: Bool) {
        let isOn = isOn && settings.play.isEnabled && settings.snow.isEnabled
        guard isOn != isPlayModeOn else { return }
        isPlayModeOn = isOn
        for overlay in overlays {
            overlay.seasonView.isPlayModeOn = isOn
        }

        playTimeout?.invalidate()
        for monitor in escapeMonitors { NSEvent.removeMonitor(monitor) }
        escapeMonitors.removeAll()

        if isOn {
            lastPlayTime = Date()
            hud.show(on: overlayUnderPointer?.screen ?? NSScreen.main, holdKeys: settings.play.holdKeys)
            // Stops on its own after a couple of quiet minutes, so the desktop never stays blocked.
            playTimeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, Date().timeIntervalSince(self.lastPlayTime) > 150 else { return }
                    self.setPlayMode(false)
                }
            }
            // Escape stops it. The global monitor needs Accessibility access; the local one doesn't.
            let handler: (NSEvent) -> Void = { [weak self] event in
                if event.keyCode == 53 { self?.setPlayMode(false) }
            }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) { escapeMonitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: {
                    handler($0)
                    return $0
                })
            {
                escapeMonitors.append(local)
            }
        } else {
            hud.hide()
        }
        onPlayModeChange?(isOn)
    }

    // MARK: Overlays

    /// The displays that show anything with the current settings.
    private func displaysToShow() -> [DisplayInfo] {
        guard settings.hasVisibleEffects, !isSuspended else { return [] }
        return DisplayInfo.connected.filter { settings.resolved(for: $0).hasVisibleEffects }
    }

    private func rebuildOverlays() {
        for overlay in overlays {
            overlay.seasonView.stop()
            overlay.orderOut(nil)
        }
        overlays.removeAll()

        let shown = Set(displaysToShow().map(\.id))
        guard !shown.isEmpty else { return }
        guard let metal else {
            Logger.app.error("Can't draw anything without Metal")
            return
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for screen in NSScreen.screens where shown.contains(DisplayInfo(screen: screen).id) {
            let display = DisplayInfo(screen: screen)
            let view = SeasonView(screen: screen, metal: metal, desktop: desktop, music: music, settings: settings.resolved(for: display))
            view.isLowPowerModeEnabled = lowPower
            view.isPlayModeOn = isPlayModeOn
            view.onEndPlay = { [weak self] in self?.setPlayMode(false) }
            view.onPlayed = { [weak self] in self?.lastPlayTime = Date() }
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

    // MARK: Santa

    /// Picks a random time for Santa's next flight, around the chosen frequency.
    private func scheduleSleigh() {
        sleighTimer?.invalidate()
        sleighTimer = nil
        guard settings.extras.sleigh else { return }
        let interval = settings.extras.sleighFrequency.interval * Double.random(in: 0.6...1.4)
        sleighTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.overlays.filter(\.seasonView.canLaunchSleigh).randomElement()?.seasonView.launchSleigh()
                self.scheduleSleigh()
            }
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
        scheduleSleigh()
    }

    @objc private func screensDidChange() {
        rebuildOverlays()
    }

    @objc private func suspend() {
        isSuspended = true
        setPlayMode(false)
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
