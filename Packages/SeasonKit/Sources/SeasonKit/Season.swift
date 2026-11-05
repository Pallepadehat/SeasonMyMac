/// A season the app can show on the desktop.
///
/// Christmas is here today; the others are on the roadmap. Adding one means
/// writing its simulation (like ``SnowWorld`` and ``LightString``), drawing it
/// in the app, and flipping ``isAvailable``.
public enum Season: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Falling snow and strings of holiday lights.
    case christmas
    /// Bats, fog and flickering jack-o'-lantern lights. Coming soon.
    case halloween
    /// Fireworks and confetti at midnight. Coming soon.
    case newYear

    public var id: Self { self }

    /// Whether the season can be turned on yet.
    public var isAvailable: Bool {
        self == .christmas
    }

    /// SF Symbol that represents the season, also used in the menu bar.
    public var symbolName: String {
        switch self {
        case .christmas: "snowflake"
        case .halloween: "moon.stars.fill"
        case .newYear: "sparkles"
        }
    }
}
