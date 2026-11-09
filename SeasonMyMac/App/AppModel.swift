import AppKit
import OSLog
import Observation
import SeasonKit
import ServiceManagement

/// The app's state. Views bind to ``settings``; every change is saved and
/// handed to the ``OverlayManager``.
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            overlays.apply(settings)
            if settings.needsDock, !oldValue.needsDock {
                askForAccessibilityOnce()
            }
        }
    }

    /// Accessibility access lets snow and lights find the Dock exactly.
    private(set) var isAccessibilityGranted: Bool

    /// Snow Play: the pointer grabs snow without holding any keys.
    private(set) var isPlayModeOn = false

    /// Today, refreshed so the Christmas countdown ticks over at midnight.
    private(set) var today = Date()

    let updater = Updater()

    /// What's playing in Apple Music or Spotify, for the lights.
    var music: MusicSync { overlays.music }

    var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchesAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.app.error("Couldn't update Open at Login: \(error)")
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let overlays: OverlayManager

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = SettingsStore(defaults: defaults)
        let saved = store.load()
        settings = saved
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        overlays = OverlayManager(settings: saved)
        isAccessibilityGranted = overlays.desktop.dockLocator.isAccessGranted
        overlays.onPlayModeChange = { [weak self] isOn in self?.isPlayModeOn = isOn }
    }

    /// Shows the effects and, the first time, asks for Accessibility access.
    func start() {
        updater.start()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !Calendar.current.isDate(self.today, inSameDayAs: Date()) else { return }
                self.today = Date()
            }
        }
        overlays.apply(settings)
        if settings.needsDock {
            askForAccessibilityOnce()
        }
    }

    func shakeOffAllSnow() {
        overlays.shakeOffAllSnow()
    }

    // MARK: Winter fun

    func setPlayMode(_ isOn: Bool) {
        overlays.setPlayMode(isOn)
    }

    func buildSnowman() {
        overlays.buildSnowman()
    }

    func clearSnowmen() {
        overlays.clearSnowmen()
    }

    func letItSnow() {
        overlays.letItSnow()
    }

    func callSanta() {
        overlays.callSanta()
    }

    /// Opens a present in the middle of the screen with the pointer.
    func openPresent() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        GiftReveal.shared.show(at: NSPoint(x: frame.midX, y: frame.midY - 160), on: screen)
    }

    /// Whole days until Christmas Day: 0 on the day itself.
    var daysUntilChristmas: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let year = calendar.component(.year, from: start)
        var christmas = calendar.date(from: DateComponents(year: year, month: 12, day: 25)) ?? start
        if christmas < start {
            christmas = calendar.date(from: DateComponents(year: year + 1, month: 12, day: 25)) ?? start
        }
        return calendar.dateComponents([.day], from: start, to: christmas).day ?? 0
    }

    // MARK: Displays

    /// Changes what one display shows, switching to per-display choices.
    func setEffects(_ effects: DisplayEffects, for display: DisplayInfo) {
        if settings.visibility.displays != .custom {
            // Start from what each display shows now, so nothing else changes.
            for other in DisplayInfo.connected where settings.visibility.displayEffects[other.id] == nil {
                let showsAll = settings.visibility.displays == .all || other.isMain
                settings.visibility.displayEffects[other.id] =
                    showsAll ? DisplayEffects() : DisplayEffects(snow: false, snowPlay: false, dockLights: false, topLights: false, frost: false, sleigh: false)
            }
            settings.visibility.displays = .custom
        }
        settings.visibility.displayEffects[display.id] = effects
    }

    func identifyDisplays() {
        DisplayIdentifier.show()
    }

    // MARK: Accessibility

    /// Shows the system prompt and opens the right pane of System Settings.
    func requestAccessibility() {
        overlays.desktop.dockLocator.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Re-checks Accessibility access, which the user grants in System Settings.
    func refreshAccessibility() {
        let granted = overlays.desktop.dockLocator.isAccessGranted
        if granted != isAccessibilityGranted {
            isAccessibilityGranted = granted
        }
    }

    private func askForAccessibilityOnce() {
        let key = "didAskForAccessibility"
        guard !isAccessibilityGranted, !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        overlays.desktop.dockLocator.requestAccess()
    }

    // MARK: App rules

    func addRule(forAppAt url: URL) {
        guard
            let bundle = Bundle(url: url),
            let identifier = bundle.bundleIdentifier,
            identifier != Bundle.main.bundleIdentifier
        else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        addRule(AppRule(bundleIdentifier: identifier, name: name))
    }

    func addRule(_ rule: AppRule) {
        guard !settings.visibility.appRules.contains(where: { $0.id == rule.id }) else { return }
        settings.visibility.appRules.append(rule)
        settings.visibility.appRules.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func removeRules(_ ids: Set<AppRule.ID>) {
        settings.visibility.appRules.removeAll { ids.contains($0.id) }
    }

    func resetToDefaults() {
        settings = AppSettings()
    }
}
