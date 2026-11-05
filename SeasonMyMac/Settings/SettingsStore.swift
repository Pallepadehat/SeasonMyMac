import Foundation
import OSLog

/// Saves ``AppSettings`` to `UserDefaults` as JSON.
///
/// Saved values are merged over the defaults before decoding, so settings
/// added in a later version get their default instead of failing to load.
struct SettingsStore {
    private let defaults: UserDefaults
    private let key = "settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            let saved = try JSONSerialization.jsonObject(with: data)
            let fallback = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings()))
            let merged = try JSONSerialization.data(withJSONObject: Self.merge(saved, over: fallback))
            return try JSONDecoder().decode(AppSettings.self, from: merged)
        } catch {
            Logger.app.error("Couldn't read saved settings, using defaults: \(error)")
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            Logger.app.error("Couldn't save settings: \(error)")
        }
    }

    /// Recursively overlays `value` on `base`, keeping keys that `value` lacks.
    private static func merge(_ value: Any, over base: Any) -> Any {
        guard let value = value as? [String: Any], let base = base as? [String: Any] else { return value }
        return base.merging(value) { baseValue, newValue in
            merge(newValue, over: baseValue)
        }
    }
}
