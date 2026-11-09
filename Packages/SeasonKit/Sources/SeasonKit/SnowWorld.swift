import Foundation

/// The complete snow simulation for one screen.
///
/// Each frame the owner calls ``step(dt:cursor:)``. Whenever the windows on
/// screen change, it also calls ``updateSurfaces(_:sampleInterval:keeping:)``.
/// The renderer then reads ``flakes`` and ``piles``.
///
/// Coordinates are screen-local points with the origin in the top-left corner.
public struct SnowWorld: Sendable {
    public var configuration: SnowConfiguration

    /// 0 is a few lonely flakes, 1 is a blizzard.
    public var intensity: Float = 0.5

    public private(set) var size: SIMD2<Float>
    public private(set) var flakes: [Flake] = []
    public internal(set) var piles: [SnowPile] = []

    // MARK: Play

    /// Tunables for snowballs, snowmen and splats.
    public var play = PlayConfiguration()

    /// Snowballs (and presents) in the world: held, flying or resting.
    public internal(set) var snowballs: [Snowball] = []
    public internal(set) var snowmen: [Snowman] = []
    /// Splats of snow stuck to the screen's edges or a window, fading away.
    public internal(set) var splats: [Splat] = []
    /// Short-lived, coloured glints: a snowman coming to life, a present opening.
    public internal(set) var sparkles: [Sparkle] = []

    var heldID: Int?
    /// The snowman being carried, and where on it the pointer took hold.
    var heldSnowmanID: Int?
    var heldSnowmanGrip: SIMD2<Float> = .zero
    var heldTarget: SIMD2<Float> = .zero
    var nextBodyID = 1
    /// Snowballs and snowmen on windows that are out of sight, like their snow.
    var stashedSnowballs: [SurfaceID: [Snowball]] = [:]
    var stashedSnowmen: [SurfaceID: [Snowman]] = [:]

    /// Snow on windows that are out of sight but still exist (on another
    /// Space, minimized, or hidden). It comes back when the window does.
    private var stashedPiles: [SurfaceID: SnowPile] = [:]

    /// A surface that hasn't moved for this long is considered at rest.
    private let stopDelay: Float = 0.07

    var random: SplitMix64
    var time: Float = 0
    private var spawnBudget: Float = 0
    private var lastCursor: SIMD2<Float>?
    private var clumpCount = 0

    public init(
        size: SIMD2<Float>,
        configuration: SnowConfiguration = SnowConfiguration(),
        seed: UInt64 = UInt64.random(in: .min ... .max)
    ) {
        self.size = size
        self.configuration = configuration
        random = SplitMix64(seed: seed)
    }

    // MARK: State

    /// `true` while something on screen moves fast enough to deserve a high
    /// frame rate: tumbling clumps, or snow riding on a window being dragged.
    public var isAnimatingQuickly: Bool {
        clumpCount >= 20 || piles.contains { time - $0.lastMotionTime < 0.3 } || isPlayAnimating
    }

    /// `true` when there's no settled snow anywhere on screen.
    public var hasNoSettledSnow: Bool {
        piles.allSatisfy(\.isEmpty)
    }

    // MARK: Simulation

    /// Fills the sky with flakes so the scene doesn't start empty.
    public mutating func prewarm() {
        let averageFallTime = size.y / (configuration.fallSpeed.lowerBound * configuration.fallSpeedScale)
        let count = Int(spawnRate * averageFallTime * 0.6)
        for _ in 0..<min(count, configuration.maxFlakes / 2) {
            var flake = makeSkyFlake()
            flake.position.y = Float.random(in: 0...size.y, using: &random)
            flakes.append(flake)
        }
    }

    /// Advances the simulation by `dt` seconds.
    ///
    /// - Parameter cursor: The mouse position on this screen, or `nil` when the
    ///   mouse is on another screen.
    public mutating func step(dt: Float, cursor: SIMD2<Float>?) {
        guard dt > 0 else { return }
        time += dt

        spawnFlakes(dt: dt)
        moveFlakes(dt: dt)
        settleStoppedSurfaces()
        brushSnow(with: cursor, dt: dt)
        stepPlay(dt: dt)
    }

    /// Flakes per second for the current screen width and intensity.
    private var spawnRate: Float {
        configuration.flakesPerSecondPer1000Points * size.x / 1000 * intensity
    }

    /// A shifting breeze: the prevailing direction plus two out-of-phase gusts.
    private var wind: Float {
        let gust = sin(time * 0.05) * 0.65 + sin(time * 0.17 + 1.3) * 0.35
        let bias = configuration.windBias
        return (bias + gust * (1 - abs(bias) * 0.5)) * configuration.windSpeed
    }

    /// Where new flakes may appear horizontally. With a steady wind, flakes
    /// drift sideways as they fall, so they're spawned further upwind.
    private var spawnRange: ClosedRange<Float> {
        let fallTime = size.y / (configuration.fallSpeed.upperBound * configuration.fallSpeedScale)
        let drift = configuration.windBias * configuration.windSpeed * fallTime
        return (min(0, -drift) - 60)...(max(size.x, size.x - drift) + 60)
    }

    private mutating func spawnFlakes(dt: Float) {
        let range = spawnRange
        let widthFactor = (range.upperBound - range.lowerBound) / max(size.x, 1)
        spawnBudget += spawnRate * widthFactor * dt
        while spawnBudget >= 1 {
            spawnBudget -= 1
            guard flakes.count < configuration.maxFlakes else { continue }
            flakes.append(makeSkyFlake())
        }
    }

    private mutating func makeSkyFlake() -> Flake {
        let config = configuration
        let depth = Float.random(in: 0...1, using: &random)
        // Bias toward small flakes; big, close ones are rare and special.
        let sizeFactor = depth * depth
        let radius = (config.flakeRadius.lowerBound + (config.flakeRadius.upperBound - config.flakeRadius.lowerBound) * sizeFactor) * config.flakeSizeScale
        let speed = (config.fallSpeed.lowerBound + (config.fallSpeed.upperBound - config.fallSpeed.lowerBound) * depth) * config.fallSpeedScale

        return Flake(
            position: SIMD2(Float.random(in: spawnRange, using: &random), -radius - 4),
            radius: radius,
            opacity: 0.35 + 0.6 * depth,
            kind: .flake,
            velocity: SIMD2(0, speed),
            depth: depth,
            terminalSpeed: speed * Float.random(in: 0.85...1.15, using: &random),
            swayPhase: Float.random(in: 0...(2 * .pi), using: &random),
            swayFrequency: Float.random(in: 0.6...1.8, using: &random),
            snowAmount: Float.pi * radius * radius * config.settleFactor * config.accumulationRate,
            settleDelay: 0,
            canSettle: depth >= config.backgroundDepth
        )
    }

    private mutating func moveFlakes(dt: Float) {
        let wind = wind
        var spills: [SnowPile.Spill] = []

        // Compact the array in place: survivors are moved to the front, so no
        // memory is allocated per frame.
        var survivorCount = 0
        var clumps = 0
        for index in flakes.indices {
            var flake = flakes[index]
            let previousY = flake.position.y
            flake.advance(dt: dt, wind: wind, configuration: configuration)

            if flake.canSettle, flake.settleDelay <= 0, flake.velocity.y > 0,
                let landing = landingSite(for: flake, previousY: previousY)
            {
                let amount = flake.snowAmount / configuration.columnWidth
                spills += piles[landing.pile].deposit(amount, atColumn: landing.column)
                continue
            }

            let isOffScreen = flake.position.y > size.y + 20 || flake.position.x < -400 || flake.position.x > size.x + 400
            if isOffScreen { continue }

            flakes[survivorCount] = flake
            survivorCount += 1
            if flake.kind == .clump { clumps += 1 }
        }
        flakes.removeLast(flakes.count - survivorCount)
        clumpCount = clumps

        for spill in spills {
            spawnSpill(spill)
        }
    }

    /// Finds the pile column whose snow surface the flake passed through this frame.
    private func landingSite(for flake: Flake, previousY: Float) -> (pile: Int, column: Int)? {
        for index in piles.indices {
            let pile = piles[index]
            guard
                let column = pile.column(at: flake.position.x),
                pile.isVisible[column]
            else { continue }

            let top = pile.top(ofColumn: column)
            if previousY <= top, flake.position.y >= top {
                return (index, column)
            }
        }
        return nil
    }

    // MARK: Surfaces

    /// Syncs piles with the surfaces currently on screen.
    ///
    /// - Snow rides along with a window that moves gently, and is shaken loose
    ///   when the window speeds up or stops abruptly. Loose snow keeps the
    ///   momentum it had.
    /// - Resizing jostles snow off, and snow with nothing under it falls.
    /// - Snow that gets covered by another window is pushed off.
    /// - Snow on windows in `hiddenIDs` (still open, just out of sight) is put
    ///   aside and restored when the window comes back. Snow on any other
    ///   surface that vanished falls.
    ///
    /// - Parameter sampleInterval: Seconds between this window sample and the previous one.
    public mutating func updateSurfaces(
        _ surfaces: [Surface],
        sampleInterval: Float,
        keeping hiddenIDs: Set<SurfaceID> = []
    ) {
        var previous = Dictionary(uniqueKeysWithValues: piles.map { ($0.surfaceID, $0) })
        var next: [SnowPile] = []
        next.reserveCapacity(surfaces.count)

        for surface in surfaces {
            var pile: SnowPile
            if var existing = previous.removeValue(forKey: surface.id) {
                follow(&existing, to: surface, sampleInterval: sampleInterval)
                pile = existing
            } else if var stashed = stashedPiles.removeValue(forKey: surface.id) {
                restore(&stashed, on: surface)
                pile = stashed
            } else {
                pile = SnowPile(surface: surface, columnWidth: configuration.columnWidth, maxSlope: configuration.maxColumnSlope)
            }

            spawnSnow(from: pile.updateVisibility(surface.visibleSpans), velocity: pile.velocity)
            next.append(pile)
        }

        for (id, var vanished) in previous {
            if hiddenIDs.contains(id) {
                vanished.velocity = .zero
                vanished.lastMotionTime = -.infinity
                stashedPiles[id] = vanished
            } else {
                spawnSnow(from: vanished.removeAll(), velocity: .zero)
            }
        }

        // Windows that were stashed and are no longer around have been closed.
        stashedPiles = stashedPiles.filter { hiddenIDs.contains($0.key) }
        piles = next
        syncPlayWithSurfaces(keeping: hiddenIDs)
    }

    /// Updates a pile whose surface is still on screen.
    private mutating func follow(_ pile: inout SnowPile, to surface: Surface, sampleInterval: Float) {
        guard !pile.hasSameGeometry(as: surface) else { return }

        guard pile.hasSameWidth(as: surface) else {
            // Resizing: jostle some snow loose, and drop what lost its footing.
            spawnSnow(from: pile.resize(to: surface), velocity: .zero)
            spawnSnow(from: pile.shed(fraction: configuration.resizeShedFraction), velocity: .zero)
            return
        }

        let displacement = SIMD2(surface.minX - pile.minX, surface.y - pile.y)

        // A window that jumped between two slow samples (snapped by a keyboard
        // shortcut, say) moved too abruptly to follow: its snow falls.
        if sampleInterval > 0.1, length(displacement) > 4 {
            spawnSnow(from: pile.removeAll(), velocity: .zero)
            pile.move(to: surface)
            return
        }

        // Moving: estimate the window's velocity, smoothed so the jitter of a
        // hand-held drag doesn't read as shaking.
        let rawVelocity = displacement / max(sampleInterval, 1.0 / 120)
        let wasMoving = time - pile.lastMotionTime < stopDelay + sampleInterval
        let previousVelocity = wasMoving ? pile.velocity : .zero
        let velocity = previousVelocity + (rawVelocity - previousVelocity) * 0.5

        pile.move(to: surface)
        pile.velocity = velocity
        pile.lastMotionTime = time
        shake(&pile, velocityChange: velocity - previousVelocity, inertia: previousVelocity)
    }

    /// Puts a stashed pile back on its window.
    private mutating func restore(_ pile: inout SnowPile, on surface: Surface) {
        if pile.hasSameWidth(as: surface) {
            pile.move(to: surface)
        } else {
            spawnSnow(from: pile.resize(to: surface), velocity: .zero)
        }
    }

    /// Detects windows that stopped moving: the sudden stop flings snow forward.
    private mutating func settleStoppedSurfaces() {
        for index in piles.indices {
            let pile = piles[index]
            guard pile.velocity != .zero, time - pile.lastMotionTime > stopDelay else { continue }

            var stopped = pile
            stopped.velocity = .zero
            shake(&stopped, velocityChange: -pile.velocity, inertia: pile.velocity)
            piles[index] = stopped
        }
    }

    /// Knocks snow loose in proportion to how sharply the surface's velocity changed.
    ///
    /// - Parameter inertia: The velocity the snow had before the change. Loose
    ///   snow keeps it, so it's left behind or flung forward.
    private mutating func shake(_ pile: inout SnowPile, velocityChange: SIMD2<Float>, inertia: SIMD2<Float>) {
        // Accelerating downward pulls the surface out from under the snow;
        // accelerating upward presses snow onto it.
        let effective = SIMD2(
            velocityChange.x,
            velocityChange.y > 0 ? velocityChange.y * 1.4 : velocityChange.y * 0.4
        )
        let fraction = (length(effective) - configuration.shakeThreshold) / configuration.shakeRange
        guard fraction > 0 else { return }
        spawnSnow(from: pile.shed(fraction: min(1, fraction)), velocity: inertia)
    }

    /// Knocks all settled snow loose at once.
    public mutating func shakeOffAllSnow() {
        for index in piles.indices {
            spawnSnow(from: piles[index].removeAll(), velocity: SIMD2(0, -120))
        }
        shakeLooseEverything()
    }

    // MARK: Cursor

    private mutating func brushSnow(with cursor: SIMD2<Float>?, dt: Float) {
        defer { lastCursor = cursor }
        guard configuration.cursorBrushesSnow, !isHolding, let cursor, let lastCursor else { return }

        let velocity = (cursor - lastCursor) / dt
        guard length(velocity) >= configuration.brushMinimumSpeed else { return }

        for index in piles.indices {
            let released = piles[index].removeSnow(near: cursor, radius: configuration.brushRadius)
            guard !released.isEmpty else { continue }
            let push = clamped(velocity * 0.35, maxLength: 400) + SIMD2(0, -90)
            spawnSnow(from: released, velocity: push)
        }
    }

    // MARK: Loose snow

    /// Turns released snow into falling clumps and a puff of drifting powder.
    /// Together they carry the snow's mass, so it can pile up again below.
    mutating func spawnSnow(from released: [SnowPile.ReleasedSnow], velocity: SIMD2<Float>) {
        let inherited = clamped(velocity, maxLength: 700)
        for slice in released {
            let clumpShare = slice.area * (1 - configuration.powderFraction)
            let powderShare = slice.area * configuration.powderFraction

            for _ in 0..<randomCount(clumpShare / configuration.clumpArea) {
                guard flakes.count < configuration.maxFlakes else { return }
                flakes.append(makeClump(at: randomPoint(in: slice), velocity: inherited))
            }
            for _ in 0..<randomCount(powderShare / configuration.powderArea) {
                guard flakes.count < configuration.maxFlakes else { return }
                flakes.append(makePowder(at: randomPoint(in: slice), velocity: inherited))
            }
        }
    }

    mutating func spawnSpill(_ spill: SnowPile.Spill) {
        let probability = spill.amount * configuration.columnWidth / configuration.clumpArea
        guard flakes.count < configuration.maxFlakes, Float.random(in: 0...1, using: &random) < probability else { return }
        flakes.append(makeClump(at: SIMD2(spill.x, spill.y), velocity: SIMD2(0, 10)))
    }

    private mutating func makeClump(at position: SIMD2<Float>, velocity: SIMD2<Float>) -> Flake {
        let jitter = SIMD2(Float.random(in: -25...25, using: &random), Float.random(in: -30...10, using: &random))
        return Flake(
            position: position,
            radius: Float.random(in: 1.3...3.0, using: &random),
            opacity: Float.random(in: 0.85...1, using: &random),
            kind: .clump,
            velocity: velocity + jitter,
            depth: 1,
            terminalSpeed: configuration.clumpTerminalSpeed * Float.random(in: 0.75...1, using: &random),
            swayPhase: 0,
            swayFrequency: 0,
            snowAmount: configuration.clumpArea * 0.9,
            settleDelay: configuration.resettleDelay,
            canSettle: true
        )
    }

    /// Powder bursts outward a little, then drifts down like a light flake.
    private mutating func makePowder(at position: SIMD2<Float>, velocity: SIMD2<Float>) -> Flake {
        let burst = SIMD2(Float.random(in: -45...45, using: &random), Float.random(in: -60...0, using: &random))
        return Flake(
            position: position,
            radius: Float.random(in: 0.6...1.3, using: &random),
            opacity: Float.random(in: 0.55...0.85, using: &random),
            kind: .flake,
            velocity: velocity * 0.5 + burst,
            depth: Float.random(in: 0.7...1, using: &random),
            terminalSpeed: Float.random(in: 30...60, using: &random) * configuration.fallSpeedScale,
            swayPhase: Float.random(in: 0...(2 * .pi), using: &random),
            swayFrequency: Float.random(in: 1...2.5, using: &random),
            snowAmount: configuration.powderArea * 0.9,
            settleDelay: configuration.resettleDelay,
            canSettle: true
        )
    }

    private mutating func randomPoint(in slice: SnowPile.ReleasedSnow) -> SIMD2<Float> {
        SIMD2(
            slice.x + Float.random(in: -slice.width / 2...slice.width / 2, using: &random),
            Float.random(in: slice.top...slice.bottom, using: &random)
        )
    }

    /// Rounds `expected` up or down at random so the average count is exact.
    private mutating func randomCount(_ expected: Float) -> Int {
        let whole = expected.rounded(.down)
        return Int(whole) + (Float.random(in: 0..<1, using: &random) < expected - whole ? 1 : 0)
    }
}
