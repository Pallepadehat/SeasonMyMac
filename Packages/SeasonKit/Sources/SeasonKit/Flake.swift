import Foundation

/// A single particle of snow: a flake drifting down from the sky, a clump
/// knocked off a window, or a puff of powder.
public struct Flake: Sendable {
    public enum Kind: Sendable {
        /// Floats down at terminal speed, swaying in the wind.
        case flake
        /// A dense bit of snow that falls under gravity.
        case clump
    }

    public internal(set) var position: SIMD2<Float>
    public internal(set) var radius: Float
    public internal(set) var opacity: Float

    var kind: Kind
    var velocity: SIMD2<Float>

    /// 0 is far away, 1 is right in front of the viewer.
    var depth: Float

    var terminalSpeed: Float
    var swayPhase: Float
    var swayFrequency: Float

    /// Settled area (pt²) this particle adds to a pile when it lands.
    var snowAmount: Float

    /// Time left before this particle is allowed to settle on a surface.
    var settleDelay: Float

    var canSettle: Bool

    /// Integrates the particle forward by `dt` seconds.
    mutating func advance(dt: Float, wind: Float, configuration: SnowConfiguration) {
        switch kind {
        case .clump:
            velocity.y = min(velocity.y + configuration.gravity * dt, terminalSpeed)
            velocity.x *= max(0, 1 - 1.6 * dt)  // air drag
        case .flake:
            swayPhase += swayFrequency * dt
            let target = SIMD2<Float>(
                wind * depth + sin(swayPhase) * configuration.swaySpeed * depth,
                terminalSpeed
            )
            // Ease toward the target velocity so flakes feel weightless.
            velocity += (target - velocity) * min(1, 2.5 * dt)
        }

        position += velocity * dt
        settleDelay -= dt
    }
}
