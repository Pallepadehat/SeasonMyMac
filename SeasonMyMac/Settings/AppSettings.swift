import SeasonKit

/// Everything the user can customise. Persisted as JSON by ``SettingsStore``.
///
/// To add a setting, give it a default value here. Older saved settings simply
/// pick up the default, so nobody's preferences are ever reset.
struct AppSettings: Codable, Equatable {
    var season = Season.christmas
    var snow = SnowSettings()
    var lights = LightSettings()
    var play = PlaySettings()
    var extras = WinterExtras()
    var visibility = VisibilitySettings()
    var performance = PerformanceMode.balanced

    /// Whether anything at all needs to be drawn.
    var hasVisibleEffects: Bool {
        snow.isEnabled || lights.isShowing || extras.frost || extras.sleigh
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
    /// How the string sits on the Dock.
    var dockStyle = DockLightStyle.rim
    /// Flash and change colour to the beat of Apple Music or Spotify.
    var dancesToMusic = true

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

/// How the lights sit on the Dock.
enum DockLightStyle: String, Codable, CaseIterable, Identifiable {
    /// Along the Dock's rounded rim, bulbs standing up: never in front of an icon.
    case rim
    /// Clipped above each icon, a bulb hanging in every gap.
    case draped

    var id: Self { self }
}

struct VisibilitySettings: Codable, Equatable {
    var hidesInFullScreen = true
    var displays = DisplayMode.all
    var appRules: [AppRule] = []
    /// What each display shows when ``displays`` is `.custom`, keyed by ``DisplayInfo/id``.
    var displayEffects: [String: DisplayEffects] = [:]

    enum DisplayMode: String, Codable, CaseIterable, Identifiable {
        case all
        case main
        /// Chosen display by display.
        case custom

        var id: Self { self }
    }

    func effects(for displayID: String) -> DisplayEffects {
        displayEffects[displayID] ?? DisplayEffects()
    }
}

/// What one display shows.
struct DisplayEffects: Codable, Equatable {
    var snow = true
    var snowPlay = true
    var dockLights = true
    var topLights = true
    var frost = true
    var sleigh = true

    var showsAnything: Bool {
        snow || dockLights || topLights || frost || sleigh
    }
}

/// Snowballs and snowmen.
struct PlaySettings: Codable, Equatable {
    var isEnabled = true
    /// Hold these keys to grab snow with the pointer. (Or turn on Snow Play from the menu bar.)
    var holdKeys = PlayKeys.controlOption
    /// 0.5...2.
    var throwPower = 1.0
    var splats = true
    /// 1...12.
    var maxSnowmen = 6.0

    var hat = SnowmanHat.random
    var scarf = ScarfColor.random
    var hasArms = true
    var hasCarrotNose = true
}

enum PlayKeys: String, Codable, CaseIterable, Identifiable {
    case off
    case controlOption
    case optionCommand
    case controlCommand

    var id: Self { self }
}

enum SnowmanHat: String, Codable, CaseIterable, Identifiable {
    case random, topHat, santaHat, beanie, none
    var id: Self { self }
}

enum ScarfColor: String, Codable, CaseIterable, Identifiable {
    case random, red, green, blue, gold, none
    var id: Self { self }
}

/// The rest of the winter magic.
struct WinterExtras: Codable, Equatable {
    /// Frost creeping in from the corners of the screen.
    var frost = false
    /// How far it reaches, 0.2...1.
    var frostAmount = 0.5

    /// Santa's sleigh flies past now and then.
    var sleigh = true
    var sleighFrequency = SleighFrequency.sometimes
    var sleighDropsGifts = true

    /// Days until Christmas next to the menu bar icon.
    var countdownInMenuBar = false
    var countdownStyle = CountdownStyle.full
}

enum SleighFrequency: String, Codable, CaseIterable, Identifiable {
    case rarely, sometimes, often
    var id: Self { self }

    /// Average seconds between flights.
    var interval: Double {
        switch self {
        case .rarely: 45 * 60
        case .sometimes: 15 * 60
        case .often: 4 * 60
        }
    }
}

extension AppSettings {
    /// These settings narrowed to what one display shows.
    func resolved(for display: DisplayInfo) -> AppSettings {
        var settings = self
        let effects: DisplayEffects
        switch visibility.displays {
        case .all: effects = DisplayEffects()
        case .main:
            effects =
                display.isMain
                ? DisplayEffects() : DisplayEffects(snow: false, snowPlay: false, dockLights: false, topLights: false, frost: false, sleigh: false)
        case .custom: effects = visibility.effects(for: display.id)
        }
        settings.snow.isEnabled = snow.isEnabled && effects.snow
        settings.play.isEnabled = play.isEnabled && effects.snowPlay && settings.snow.isEnabled
        settings.lights.onDock = lights.onDock && effects.dockLights
        settings.lights.alongTop = lights.alongTop && effects.topLights && (lights.topOnAllDisplays || display.isMain)
        settings.extras.frost = extras.frost && effects.frost
        settings.extras.sleigh = extras.sleigh && effects.sleigh
        return settings
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

/// How the Christmas countdown reads in the menu bar.
enum CountdownStyle: String, Codable, CaseIterable, Identifiable {
    /// "46 days until Christmas"
    case full
    /// "46 days"
    case short

    var id: Self { self }
}
