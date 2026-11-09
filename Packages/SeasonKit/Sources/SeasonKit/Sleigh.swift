import Foundation

/// Santa's sleigh and its reindeer flying across the screen now and then,
/// leaving a trail of sparkles and, sometimes, dropping a present.
///
/// Coordinates are screen-local points, origin top-left, y downward.
public struct Sleigh: Sendable {
    /// Something that happened during a step, for the owner to act on.
    public enum Event: Sendable, Equatable {
        case dropGift(position: SIMD2<Float>, velocity: SIMD2<Float>, style: Int)
        case sparkle(position: SIMD2<Float>, velocity: SIMD2<Float>)
    }

    public static let reindeerCount = 4

    public private(set) var isFlying = false
    /// The centre of the sleigh.
    public private(set) var position: SIMD2<Float> = .zero
    /// 1 flies right, -1 flies left.
    public private(set) var direction: Float = 1
    public private(set) var time: Float = 0

    private var speed: Float = 260
    private var altitude: Float = 0
    private var giftDrops: [Float] = []
    private var sparkleBudget: Float = 0
    private var random: SplitMix64

    public init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        random = SplitMix64(seed: seed)
    }

    /// Sets off across a screen of `size`, flying below `topInset` (the menu bar).
    public mutating func start(size: SIMD2<Float>, topInset: Float, gifts: Int) {
        direction = Bool.random(using: &random) ? 1 : -1
        speed = Float.random(in: 230...300, using: &random)
        altitude = Float.random(in: (topInset + 50)...max(topInset + 51, size.y * 0.32), using: &random)
        position = SIMD2(direction > 0 ? -Self.length : size.x + Self.length, altitude)
        time = 0
        isFlying = true
        giftDrops = (0..<max(0, gifts)).map { _ in Float.random(in: size.x * 0.15...size.x * 0.85, using: &random) }
    }

    /// Distance from the back of the sleigh to the lead reindeer's nose.
    static let length: Float = 300

    public mutating func step(dt: Float, size: SIMD2<Float>) -> [Event] {
        guard isFlying else { return [] }
        time += dt
        let previousX = position.x
        position.x += direction * speed * dt
        position.y = altitude + sin(time * 1.3) * 14

        var events: [Event] = []
        giftDrops.removeAll { x in
            let crossed = (previousX - x) * (position.x - x) <= 0
            if crossed {
                events.append(
                    .dropGift(position: position + SIMD2(0, 10), velocity: SIMD2(direction * speed * 0.6, -60), style: Int.random(in: 0...3, using: &random)))
            }
            return crossed
        }

        sparkleBudget += dt * 45
        while sparkleBudget >= 1 {
            sparkleBudget -= 1
            let back = position + SIMD2(-direction * 26, Float.random(in: -6...10, using: &random))
            events.append(
                .sparkle(position: back, velocity: SIMD2(-direction * Float.random(in: 10...40, using: &random), Float.random(in: -10...25, using: &random))))
        }

        let isPast = direction > 0 ? position.x > size.x + Self.length : position.x < -Self.length
        if isPast { isFlying = false }
        return events
    }

    public mutating func stop() {
        isFlying = false
    }

    /// Where each reindeer is, the lead one last. They bob out of step.
    public var reindeer: [SIMD2<Float>] {
        (0..<Self.reindeerCount).map { index in
            let ahead = 62 + Float(index) * 46
            let bob = sin(time * 7 + Float(index) * 1.4) * 3.5
            let lift = Float(index) * -4
            return position + SIMD2(direction * ahead, bob + lift)
        }
    }

    /// The lead reindeer's glowing red nose.
    public var noseOfLeadReindeer: SIMD2<Float> {
        (reindeer.last ?? position) + SIMD2(direction * 15, -7)
    }

    /// Whether `point` is on the sleigh or one of the reindeer.
    public func contains(_ point: SIMD2<Float>) -> Bool {
        guard isFlying else { return false }
        return ([position] + reindeer).contains { distance($0, point) < 26 }
    }
}
