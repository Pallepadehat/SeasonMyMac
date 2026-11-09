import AppKit
import SeasonKit

/// Translates the user's settings into simulation parameters.
extension SnowConfiguration {
    init(_ settings: SnowSettings) {
        self.init()
        flakeSizeScale = Float(settings.flakeSize)
        fallSpeedScale = Float(settings.fallSpeed)
        windSpeed = Float(settings.windStrength) * 60
        windBias = Float(settings.windDirection)
        maxPileHeight = Float(settings.depth)
        accumulationRate = Float(settings.accumulation)
        stickiness = Float(settings.stickiness)
        cursorBrushesSnow = settings.cursorBrushesSnow
    }
}

extension LightString {
    mutating func apply(_ settings: LightSettings) {
        if palette != settings.palette { palette = settings.palette }
        animation = settings.effect
        brightness = Float(settings.brightness)
        swings = settings.swings
    }
}

extension LightSettings {
    /// Base radius of a bulb, in points.
    var bulbPointSize: Float {
        4.4 * Float(bulbSize)
    }
}

extension PlayKeys {
    var modifiers: NSEvent.ModifierFlags? {
        switch self {
        case .off: nil
        case .controlOption: [.control, .option]
        case .optionCommand: [.option, .command]
        case .controlCommand: [.control, .command]
        }
    }

    /// Whether exactly these keys are held down right now.
    var arePressed: Bool {
        guard let modifiers else { return false }
        return NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]) == modifiers
    }

    /// The keys as symbols, like "⌃⌥".
    var symbols: String {
        switch self {
        case .off: ""
        case .controlOption: "⌃⌥"
        case .optionCommand: "⌥⌘"
        case .controlCommand: "⌃⌘"
        }
    }
}
