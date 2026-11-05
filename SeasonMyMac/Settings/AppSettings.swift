import SeasonKit

/// Everything the user can customise. Persisted as JSON by ``SettingsStore``.
///
/// To add a setting, give it a default value here. Older saved settings simply
/// pick up the default, so nobody's preferences are ever reset.
struct AppSettings: Codable, Equatable {
    var season = Season.christmas
    var snow = SnowSettings()
    var lights = LightSettings()
    var visibility = VisibilitySettings()
    var performance = PerformanceMode.balanced

    /// Whether anything at all needs to be drawn.
    var hasVisibleEffects: Bool {
        snow.isEnabled || lights.isShowing
    }

    /// Whether any feature needs to know where the Dock is.
    var needsDock: Bool {
        (snow.isEnabled && snow.settlesOnDock) || (lights.isEnabled && lights.onDock)
    }
}

struct SnowSettings: Codable, Equatable {
    var isEnabled = true

    // Snowfall
    /// 0...1, from a light flurry to a blizzard.
    var intensity = 0.5
    /// Multiplier, 0.5...2.
    var flakeSize = 1.0
    /// Multiplier, 0.5...2.
    var fallSpeed = 1.0

    // Wind
    /// 0...1.
    var windStrength = 0.35
    /// -1 blows left, 0 is calm on average, 1 blows right.
    var windDirection = 0.0

    // Settling
    var settlesOnWindows = true
    var settlesOnDock = true
    /// Deepest a drift can get, in points (3...20).
    var depth = 9.0
    /// Multiplier for how fast snow piles up (0.25...4).
    var accumulation = 1.0
    /// 0 slides off at a nudge, 1 only falls off when shaken hard.
    var stickiness = 0.5

    // Interaction
    var cursorBrushesSnow = true
}

struct LightSettings: Codable, Equatable {
    var isEnabled = true
    var onDock = true
    var alongTop = false

    var palette = LightPalette.classic
    /// How the bulbs light up. (Not named `animation`, which `Binding` already uses.)
    var effect = LightAnimation.twinkle
    /// 0.2...1.
    var brightness = 0.85
    /// Multiplier, 0.6...1.6.
    var bulbSize = 1.0
    /// Multiplier for how many bulbs hang on the wire, 0.5...2.
    var density = 1.0
    var swings = true

    // Lights along the top of the screen
    /// Distance between the clips holding the wire up, in points (40...160).
    var topLoopWidth = 64.0
    /// How far the wire droops between clips, in points (2...24).
    var topDroop = 6.0
    /// `false` keeps the top lights to the main display.
    var topOnAllDisplays = true

    var isShowing: Bool {
        isEnabled && (onDock || alongTop)
    }
}

struct VisibilitySettings: Codable, Equatable {
    var hidesInFullScreen = true
    var displays = DisplayMode.all
    var appRules: [AppRule] = []

    enum DisplayMode: String, Codable, CaseIterable, Identifiable {
        case all
        case main

        var id: Self { self }
    }
}

/// A per-app exception.
struct AppRule: Codable, Equatable, Identifiable {
    enum Behavior: String, Codable, CaseIterable, Identifiable {
        /// Hide snow and lights while the app is in front.
        case pauseEffects
        /// Keep the effects, but don't let snow settle on the app's windows.
        case noSnowOnWindows

        var id: Self { self }
    }

    var bundleIdentifier: String
    var name: String
    var behavior = Behavior.pauseEffects

    var id: String { bundleIdentifier }
}

/// Trades smoothness for energy.
enum PerformanceMode: String, Codable, CaseIterable, Identifiable {
    /// Always 30 fps.
    case batterySaver
    /// 30 fps for drifting snow, 60 fps while things move fast.
    case balanced
    /// Always 60 fps.
    case smooth

    var id: Self { self }
}
