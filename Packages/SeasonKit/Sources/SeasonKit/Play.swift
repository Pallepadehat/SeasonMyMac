import Foundation

/// Tunable constants for playing in the snow: snowballs, snowmen and splats.
///
/// Distances are in points, times in seconds, y grows downward.
public struct PlayConfiguration: Sendable, Equatable {
    /// Multiplies how hard a flick throws a snowball.
    public var throwPower: Float = 1

    /// Fast snowballs burst into a splat. When off, they bounce instead.
    public var splatsEnabled = true

    /// The oldest snowman melts away when there are more than this.
    public var maxSnowmen = 6

    /// The oldest snowball melts away when there are more than this.
    public var maxSnowballs = 30

    /// How long a present waits to be opened before it fades away.
    public var giftLifetime: Float = 150

    public var gravity: Float = 1500

    /// Snowballs landing or hitting something faster than this splat.
    public var splatSpeed: Float = 780

    public var minRadius: Float = 5
    public var maxRadius: Float = 46

    /// How much smaller snow gets when it's packed into a ball.
    public var packing: Float = 0.7

    public init() {}
}

/// A ball of packed snow you can roll, throw and stack. Presents dropped by
/// Santa's sleigh use the same physics, so they're snowballs of another kind.
public struct Snowball: Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case snowball
        /// A present. `style` picks its look.
        case gift(style: Int)
    }

    public enum State: Sendable, Equatable {
        /// Following the pointer.
        case held
        case flying
        /// Sitting on a window, the Dock, or the bottom of the screen.
        case resting
    }

    public let id: Int
    public let kind: Kind
    /// The centre.
    public internal(set) var position: SIMD2<Float>
    public internal(set) var radius: Float
    /// Turns as the ball rolls, in radians.
    public internal(set) var rotation: Float = 0
    public internal(set) var state: State
    /// Squashed flat for a moment after a landing, from 0 (round) to about 0.3.
    public internal(set) var squash: Float = 0
    public internal(set) var age: Float = 0

    var velocity: SIMD2<Float> = .zero
    /// Thrown, rather than dropped. Only thrown snowballs splat.
    var isThrown = false
    /// Shrinking away into a puddle.
    var isMelting = false
    var support: Support?
    /// The velocity of the window it rests on, last frame. A sudden change shakes it off.
    var supportVelocity: SIMD2<Float> = .zero

    public var isGift: Bool {
        if case .gift = kind { return true }
        return false
    }

    /// Presents fade away when nobody opens them.
    public func opacity(lifetime: Float) -> Float {
        guard isGift else { return 1 }
        return 1 - smoothstep(lifetime - 3, lifetime, age)
    }
}

/// What a snowball or snowman is resting on.
enum Support: Sendable, Equatable {
    /// A window or the Dock; `offset` is the distance from its left end.
    case surface(SurfaceID, offset: Float)
    /// The bottom edge of the screen.
    case ground

    var surfaceID: SurfaceID? {
        if case .surface(let id, _) = self { return id }
        return nil
    }
}

/// Two or three snowballs stacked up. With three, it comes to life with a
/// face, a hat and a scarf.
public struct Snowman: Sendable, Identifiable {
    public let id: Int
    /// The bottom centre, where it touches the ground.
    public internal(set) var base: SIMD2<Float>
    /// Ball radii from the bottom up.
    public internal(set) var radii: [Float]
    /// Leaning angle in radians; positive leans right.
    public internal(set) var tilt: Float = 0
    /// Seconds since the head went on, or a negative number while it's unfinished.
    public internal(set) var completedAge: Float = -1
    /// A seed for the look: which hat, which scarf.
    public let style: UInt32
    public internal(set) var age: Float = 0

    var tiltVelocity: Float = 0
    var velocity: SIMD2<Float> = .zero
    var support: Support?
    var supportVelocity: SIMD2<Float> = .zero
    var isFalling: Bool

    /// 0 while it stands; grows to 1 as it melts away.
    public internal(set) var melt: Float = 0
    public var isMelting: Bool { melt > 0 }

    /// The ball radii as they look right now: smaller while melting, the head first.
    public var displayRadii: [Float] {
        guard melt > 0 else { return radii }
        return radii.enumerated().map { index, radius in
            let delay = Float(radii.count - 1 - index) * 0.16
            return radius * (1 - smoothstep(delay, delay + 0.62, melt))
        }
    }

    public var isComplete: Bool { radii.count >= 3 }

    /// Ball centres from the bottom up, before leaning.
    public var centers: [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []
        let radii = displayRadii
        var y = base.y
        for (index, radius) in radii.enumerated() {
            y -= index == 0 ? radius * 0.9 : radii[index - 1] * 0.78 + radius * 0.8
            result.append(SIMD2(base.x, y))
        }
        return result
    }

    /// Ball centres with the lean applied, as they're drawn.
    var leaningCenters: [SIMD2<Float>] {
        centers.map(leaning)
    }

    /// Rotates `point` around the base by the lean.
    func leaning(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let offset = point - base
        let (s, c) = (sin(tilt), cos(tilt))
        return base + SIMD2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)
    }
}

/// A splat of snow stuck where a snowball burst. It slides a little and fades.
public struct Splat: Sendable {
    public internal(set) var position: SIMD2<Float>
    public let radius: Float
    public let seed: Float
    public internal(set) var age: Float = 0
    /// The direction the splat spreads in: up for a landing, sideways on a wall.
    public let normal: SIMD2<Float>

    public static let lifetime: Float = 6

    public var opacity: Float {
        (1 - smoothstep(Self.lifetime * 0.55, Self.lifetime, age)) * min(1, age * 12 + 0.4)
    }
}

/// A short-lived glint of colour.
public struct Sparkle: Sendable {
    public internal(set) var position: SIMD2<Float>
    public let color: SIMD3<Float>
    public let size: Float
    public internal(set) var life: Float
    public let lifetime: Float
    var velocity: SIMD2<Float>
    var gravity: Float

    public var opacity: Float {
        let progress = 1 - life / lifetime
        return min(1, progress * 8) * (1 - smoothstep(0.55, 1, progress))
    }
}
