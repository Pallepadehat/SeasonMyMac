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
    }

    /// Shows the effects and, the first time, asks for Accessibility access.
    func start() {
        overlays.apply(settings)
        if settings.needsDock {
            askForAccessibilityOnce()
        }
    }

    func shakeOffAllSnow() {
        overlays.shakeOffAllSnow()
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
