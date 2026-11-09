import Foundation

/// The colours a string of lights can have.
public enum LightPalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case warmWhite
    case icy
    case candyCane
    case aurora
    case gold
    case peppermint
    case frosted
    case fireside
    case forest
    case royal
    case nordic
    case pastel
    case neon
    case rainbow

    public var id: Self { self }

    /// Linear RGB colours, repeated along the string.
    public var colors: [SIMD3<Float>] {
        switch self {
        case .classic:
            [SIMD3(0.95, 0.16, 0.14), SIMD3(0.16, 0.75, 0.3), SIMD3(1, 0.72, 0.18), SIMD3(0.2, 0.45, 0.98)]
        case .warmWhite:
            [SIMD3(1, 0.82, 0.55)]
        case .icy:
            [SIMD3(0.6, 0.85, 1), SIMD3(0.92, 0.97, 1), SIMD3(0.42, 0.66, 1)]
        case .candyCane:
            [SIMD3(0.95, 0.14, 0.2), SIMD3(1, 0.95, 0.93)]
        case .aurora:
            [SIMD3(0.3, 0.95, 0.62), SIMD3(0.36, 0.58, 1), SIMD3(0.78, 0.42, 1), SIMD3(0.22, 0.9, 0.92)]
        case .gold:
            [SIMD3(1, 0.78, 0.3), SIMD3(1, 0.88, 0.55), SIMD3(0.95, 0.62, 0.2)]
        case .peppermint:
            [SIMD3(0.95, 0.14, 0.2), SIMD3(1, 0.97, 0.95), SIMD3(0.18, 0.72, 0.36), SIMD3(1, 0.97, 0.95)]
        case .frosted:
            [SIMD3(0.82, 0.88, 0.95), SIMD3(0.45, 0.7, 1), SIMD3(0.95, 0.97, 1), SIMD3(0.62, 0.78, 0.95)]
        case .fireside:
            [SIMD3(1, 0.42, 0.12), SIMD3(1, 0.7, 0.25), SIMD3(0.9, 0.2, 0.1), SIMD3(1, 0.55, 0.2)]
        case .forest:
            [SIMD3(0.15, 0.62, 0.3), SIMD3(1, 0.8, 0.35), SIMD3(0.3, 0.8, 0.45), SIMD3(0.92, 0.3, 0.2)]
        case .royal:
            [SIMD3(0.6, 0.35, 1), SIMD3(1, 0.8, 0.35), SIMD3(0.35, 0.4, 1)]
        case .nordic:
            [SIMD3(0.9, 0.18, 0.22), SIMD3(1, 0.95, 0.88)]
        case .pastel:
            [SIMD3(1, 0.65, 0.75), SIMD3(0.65, 0.85, 1), SIMD3(0.75, 1, 0.75), SIMD3(1, 0.92, 0.6), SIMD3(0.85, 0.7, 1)]
        case .neon:
            [SIMD3(1, 0.2, 0.75), SIMD3(0.2, 0.95, 1), SIMD3(0.7, 0.3, 1), SIMD3(0.4, 1, 0.4)]
        case .rainbow:
            [SIMD3(1, 0.2, 0.2), SIMD3(1, 0.6, 0.15), SIMD3(1, 0.9, 0.2), SIMD3(0.25, 0.85, 0.35), SIMD3(0.25, 0.55, 1), SIMD3(0.65, 0.35, 1)]
        }
    }
}

/// How the bulbs light up over time.
public enum LightAnimation: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Always on.
    case steady
    /// Each bulb flickers gently on its own.
    case twinkle
    /// A wave of light runs along the string.
    case chase
    /// Colour groups slowly fade in and out.
    case breathe
    /// Now and then a bulb flashes extra bright, like frost catching the light.
    case sparkle
    /// Two groups blink in turn, like an old-fashioned string.
    case alternate
    /// The colours flow slowly along the string.
    case colorWave

    public var id: Self { self }
}

/// A light bulb hanging from the wire on its socket.
public struct LightBulb: Sendable {
    /// Where the socket is clipped onto the wire.
    public internal(set) var anchor: SIMD2<Float> = .zero
    /// Swing angle in radians; 0 hangs straight down.
    public internal(set) var angle: Float
    public internal(set) var color: SIMD3<Float>
    /// 0 is off, 1 is fully lit.
    public internal(set) var brightness: Float = 1

    /// The span of wire the bulb hangs from, and how far along it (0...1).
    var span: Int
    var position: Float

    /// Real bulbs never hang perfectly straight; each one has its own tilt.
    var restAngle: Float
    /// The direction the bulb points without any tilt: straight down when
    /// hanging, straight out from the wire when standing upright.
    var baseAngle: Float = 0
    var angularVelocity: Float = 0
    var index: Int
    var colorIndex: Int
    var twinkleSpeed: Float
    var twinklePhase: Float
}

/// A string of Christmas lights clipped up at anchor points, draping in
/// shallow scallops between them.
///
/// Bulbs hang from the wire and swing like little pendulums: the breeze
/// rocks them, and the cursor can bump them as it passes. When the anchors
/// move (the Dock gains an icon, say) the string glides to its new shape
/// rather than jumping.
public struct LightString: Sendable {
    public var palette: LightPalette = .classic {
        didSet { recolor() }
    }
    public var animation: LightAnimation = .twinkle
    /// Overall brightness, 0...1.
    public var brightness: Float = 1
    /// Whether bulbs swing in the wind and when touched.
    public var swings = true
    /// Bulbs stand up off the wire, pointing away from it (like lights along
    /// a roof line), instead of hanging down.
    public var standsUpright = false {
        didSet { if standsUpright != oldValue { updateGeometry() } }
    }
    /// The music playing on the Mac, when the lights should dance to it.
    public var music: MusicPulse? {
        didSet { if music == nil, oldValue != nil { recolor() } }
    }

    /// The wire as a polyline, ready to draw.
    public private(set) var wire: [SIMD2<Float>] = []
    public private(set) var bulbs: [LightBulb] = []
    /// Where the wire is clipped up.
    public private(set) var anchors: [SIMD2<Float>] = []

    private var targetAnchors: [SIMD2<Float>] = []
    private var sag: Float = 0
    private var bulbSpacing: Float = 0
    private var random = SplitMix64(seed: 0x11_6475)

    /// Touches closer than this to a bulb nudge it.
    private let touchRadius: Float = 14
    private let segmentsPerSpan = 10

    public init() {}

    /// `true` when nothing will change until something nudges a bulb.
    public var isAtRest: Bool {
        animation == .steady && music == nil
            && anchors == targetAnchors
            && bulbs.allSatisfy { abs($0.angle - restingAngle(of: $0)) < 0.002 && abs($0.angularVelocity) < 0.002 }
    }

    /// `true` while a bulb swings fast enough to deserve a high frame rate.
    public var isSwingingNoticeably: Bool {
        bulbs.contains { abs($0.angularVelocity) > 0.6 }
    }

    // MARK: Layout

    /// Clips the string up at `anchors`, from left to right.
    ///
    /// If only the anchor positions changed, the string glides to its new
    /// shape. If the number of anchors changed, bulbs are re-spread but keep
    /// their colours and character, starting from where the old string was.
    ///
    /// - Parameters:
    ///   - sag: How far the wire droops below the anchors at the middle of a span.
    ///   - bulbSpacing: Rough distance between neighbouring bulbs.
    public mutating func hang(between newAnchors: [SIMD2<Float>], sag: Float, bulbSpacing: Float) {
        let isSameShape = newAnchors.count == targetAnchors.count && sag == self.sag && bulbSpacing == self.bulbSpacing
        if isSameShape {
            targetAnchors = newAnchors
            return
        }

        let previousAnchors = anchors
        targetAnchors = newAnchors
        self.sag = sag
        self.bulbSpacing = bulbSpacing

        // Start from the old string's outline so the change glides in.
        anchors = newAnchors.map { anchor in
            guard let nearest = previousAnchors.min(by: { abs($0.x - anchor.x) < abs($1.x - anchor.x) }), abs(nearest.x - anchor.x) < 80 else {
                return anchor
            }
            return SIMD2(anchor.x, nearest.y)
        }
        rebuildBulbs()
        updateGeometry()
    }

    public mutating func removeAll() {
        targetAnchors = []
        anchors = []
        wire = []
        bulbs = []
        sag = 0
        bulbSpacing = 0
    }

    private mutating func rebuildBulbs() {
        let previous = bulbs
        let colors = palette.colors
        var rebuilt: [LightBulb] = []

        guard targetAnchors.count >= 2, bulbSpacing > 0 else {
            bulbs = []
            return
        }

        for span in 0..<(targetAnchors.count - 1) {
            let length = distance(targetAnchors[span + 1], targetAnchors[span])
            let count = max(1, Int((length / bulbSpacing).rounded()))
            for slot in 0..<count {
                let index = rebuilt.count
                // Keep each bulb's look when the string is re-spread, so nothing flickers.
                let character = previous.indices.contains(index) ? previous[index] : nil
                let tilt = character?.restAngle ?? Float.random(in: -0.16...0.16, using: &random)
                rebuilt.append(
                    LightBulb(
                        angle: character?.angle ?? tilt,
                        color: colors[index % colors.count],
                        span: span,
                        position: (Float(slot) + 0.5) / Float(count),
                        restAngle: tilt,
                        angularVelocity: character?.angularVelocity ?? 0,
                        index: index,
                        colorIndex: index % colors.count,
                        twinkleSpeed: character?.twinkleSpeed ?? Float.random(in: 0.5...1.3, using: &random),
                        twinklePhase: character?.twinklePhase ?? Float.random(in: 0...(2 * .pi), using: &random)
                    )
                )
            }
        }
        bulbs = rebuilt
    }

    private mutating func recolor() {
        let colors = palette.colors
        for index in bulbs.indices {
            bulbs[index].colorIndex = index % colors.count
            bulbs[index].color = colors[bulbs[index].colorIndex]
        }
    }

    /// Recomputes the wire and where each bulb hangs from the current anchors.
    private mutating func updateGeometry() {
        wire.removeAll(keepingCapacity: true)
        guard anchors.count >= 2 else { return }

        for (start, end) in zip(anchors, anchors.dropFirst()) {
            for step in 0..<segmentsPerSpan {
                wire.append(Self.point(from: start, to: end, sag: sag, at: Float(step) / Float(segmentsPerSpan)))
            }
        }
        wire.append(anchors[anchors.count - 1])

        for index in bulbs.indices {
            let bulb = bulbs[index]
            let start = anchors[bulb.span]
            let end = anchors[bulb.span + 1]
            bulbs[index].anchor = Self.point(from: start, to: end, sag: sag, at: bulb.position)
            if standsUpright {
                // Point straight out from the wire: up along the top, sideways down the sides.
                let tangent = end - start
                bulbs[index].baseAngle = atan2(tangent.y, -tangent.x)
            } else {
                bulbs[index].baseAngle = 0
            }
        }
    }

    /// A point on the drooping wire between two anchors (a parabola, which
    /// is indistinguishable from a true catenary at this scale).
    static func point(from start: SIMD2<Float>, to end: SIMD2<Float>, sag: Float, at t: Float) -> SIMD2<Float> {
        let straight = start + (end - start) * t
        return SIMD2(straight.x, straight.y + sag * 4 * t * (1 - t))
    }

    // MARK: Simulation

    /// Advances the swinging, gliding and the light animation.
    ///
    /// - Parameters:
    ///   - time: Seconds since some fixed point; drives the animation.
    ///   - wind: Current wind speed in points per second (positive blows right).
    ///   - cursor: Mouse position in the same coordinate space, if nearby.
    ///   - cursorVelocity: Mouse velocity in points per second.
    public mutating func step(dt: Float, time: Float, wind: Float, cursor: SIMD2<Float>?, cursorVelocity: SIMD2<Float>) {
        guard !bulbs.isEmpty else { return }

        glideTowardTargets(dt: dt)

        let colorCount = Float(palette.colors.count)
        for index in bulbs.indices {
            var bulb = bulbs[index]

            if swings {
                // A damped pendulum around the bulb's natural tilt, rocked a little by the breeze.
                let breeze = wind * 0.01 * (0.6 + 0.4 * sin(time * 1.3 + Float(bulb.index) * 0.7))
                let rest = restingAngle(of: bulb)
                let acceleration = -42 * sin(bulb.angle - rest) - 3.5 * bulb.angularVelocity + breeze
                bulb.angularVelocity += acceleration * dt

                if let cursor, distance(cursor, bulb.anchor + SIMD2(0, 8)) < touchRadius {
                    bulb.angularVelocity += max(-5, min(5, cursorVelocity.x * 0.005))
                }
                bulb.angle = max(rest - 1.1, min(rest + 1.1, bulb.angle + bulb.angularVelocity * dt))
            } else {
                bulb.angle = restingAngle(of: bulb)
                bulb.angularVelocity = 0
            }

            if let music {
                let colors = palette.colors
                bulb.color = colors[(bulb.colorIndex + music.beatCount) % colors.count]
                bulb.brightness = brightness * Self.level(of: bulb, dancingTo: music, bulbCount: bulbs.count)
            } else {
                let colors = palette.colors
                if animation == .colorWave {
                    bulb.color = Self.flowingColor(colors, at: Float(bulb.colorIndex) - time * 0.5)
                } else if bulb.color != colors[bulb.colorIndex % colors.count] {
                    bulb.color = colors[bulb.colorIndex % colors.count]
                }
                bulb.brightness = brightness * Self.level(of: bulb, animation: animation, time: time, colorCount: colorCount)
            }
            bulbs[index] = bulb
        }
    }

    /// The angle a bulb settles at when nothing disturbs it.
    private func restingAngle(of bulb: LightBulb) -> Float {
        bulb.baseAngle + bulb.restAngle * (standsUpright ? 0.5 : 1)
    }

    private mutating func glideTowardTargets(dt: Float) {
        guard anchors != targetAnchors, anchors.count == targetAnchors.count else { return }
        let blend = min(1, dt * 7)
        var isSettled = true
        for index in anchors.indices {
            let delta = targetAnchors[index] - anchors[index]
            if abs(delta.x) < 0.05, abs(delta.y) < 0.05 {
                anchors[index] = targetAnchors[index]
            } else {
                anchors[index] += delta * blend
                isSettled = false
            }
        }
        if isSettled { anchors = targetAnchors }
        updateGeometry()
    }

    /// How brightly a bulb shines while dancing to music, 0...1.
    ///
    /// The string works like a level meter lit from the middle outward, with
    /// every beat flashing the whole string and moving the colours along.
    private static func level(of bulb: LightBulb, dancingTo music: MusicPulse, bulbCount: Int) -> Float {
        let middle = Float(max(bulbCount - 1, 1)) / 2
        let fromMiddle = abs(Float(bulb.index) - middle) / max(middle, 1)
        let meter = smoothstep(fromMiddle - 0.15, fromMiddle + 0.1, music.level * 1.15)
        let sparkle = 0.5 + 0.5 * sin(Float(bulb.index) * 2.3 + Float(music.beatCount) * 1.7)
        return min(1, 0.12 + 0.6 * meter + 0.45 * music.beat * (0.6 + 0.4 * sparkle))
    }

    /// How brightly a bulb shines at `time` under each animation, 0...1.
    private static func level(of bulb: LightBulb, animation: LightAnimation, time: Float, colorCount: Float) -> Float {
        switch animation {
        case .steady:
            return 1
        case .twinkle:
            // Mostly on, with soft, unhurried dips, like old incandescent strings.
            let slow = sin(time * bulb.twinkleSpeed + bulb.twinklePhase)
            let shimmer = sin(time * bulb.twinkleSpeed * 2.7 + bulb.twinklePhase * 1.7)
            return 0.78 + 0.16 * slow + 0.06 * shimmer
        case .chase:
            let wave = cos((Float(bulb.index) / 6 - time * 0.7) * 2 * .pi)
            return 0.35 + 0.65 * pow(max(0, wave), 2)
        case .breathe:
            let phase = Float(bulb.colorIndex) / max(colorCount, 1) * 2 * .pi
            return 0.45 + 0.55 * (0.5 + 0.5 * sin(time * 0.9 + phase))
        case .sparkle:
            // Each bulb gets a brief, bright glint at its own random moments.
            let cycle = time * (0.25 + bulb.twinkleSpeed * 0.2) + bulb.twinklePhase
            let glint = pow(max(0, sin(cycle * 2 * .pi)), 40)
            return 0.62 + 0.38 * glint
        case .alternate:
            // Even and odd bulbs take turns, with a soft edge like warm filaments.
            let phase = sin(time * 2.2) * (bulb.index % 2 == 0 ? 1 : -1)
            return 0.22 + 0.78 * smoothstep(-0.25, 0.25, phase)
        case .colorWave:
            return 0.85 + 0.15 * sin(time * 1.2 + Float(bulb.index) * 0.4)
        }
    }

    /// A colour blended smoothly between neighbouring palette colours.
    private static func flowingColor(_ colors: [SIMD3<Float>], at position: Float) -> SIMD3<Float> {
        guard colors.count > 1 else { return colors.first ?? SIMD3(1, 1, 1) }
        let count = Float(colors.count)
        let wrapped = position - (position / count).rounded(.down) * count
        let lower = Int(wrapped) % colors.count
        let upper = (lower + 1) % colors.count
        let t = smoothstep(0, 1, wrapped - Float(Int(wrapped)))
        return colors[lower] + (colors[upper] - colors[lower]) * t
    }
}

/// What the music is doing right now, for lights that dance to it.
public struct MusicPulse: Sendable, Equatable {
    /// Loudness, 0...1, smoothed.
    public var level: Float
    /// 1 on a beat, fading to 0 before the next.
    public var beat: Float
    /// Counts beats, so colours can step along on each one.
    public var beatCount: Int

    public init(level: Float, beat: Float, beatCount: Int) {
        self.level = level
        self.beat = beat
        self.beatCount = beatCount
    }
}
