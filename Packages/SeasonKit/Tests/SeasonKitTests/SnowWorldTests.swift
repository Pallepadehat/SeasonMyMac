import Testing

@testable import SeasonKit

@Suite("Snow world")
struct SnowWorldTests {
    let frame: Float = 1.0 / 60
    let windowSurface = Surface(id: .window(7), minX: 100, maxX: 700, y: 400, visibleSpans: [100...700], maxPileHeight: 9)

    func makeWorld() -> SnowWorld {
        var world = SnowWorld(size: SIMD2(800, 600), seed: 42)
        world.intensity = 1
        return world
    }

    /// A world whose window has collected snow and where it has stopped snowing.
    func makeSnowyWorld() -> SnowWorld {
        var world = makeWorld()
        world.updateSurfaces([windowSurface], sampleInterval: frame)
        run(&world, seconds: 40)
        world.intensity = 0
        run(&world, seconds: 20)  // let everything in the air land or leave
        return world
    }

    /// Runs the simulation at 60 fps.
    func run(_ world: inout SnowWorld, seconds: Float, cursor: SIMD2<Float>? = nil) {
        for _ in 0..<Int(seconds * 60) {
            world.step(dt: frame, cursor: cursor)
        }
    }

    func settledSnow(_ world: SnowWorld) -> Float {
        world.piles.reduce(0) { $0 + $1.totalSnow }
    }

    /// Drags the window horizontally at `speed` for `seconds`, sampling every frame.
    func drag(_ world: inout SnowWorld, speed: Float, seconds: Float) -> Surface {
        var surface = windowSurface
        for _ in 0..<Int(seconds * 60) {
            surface.minX += speed * frame
            surface.maxX += speed * frame
            surface.visibleSpans = [surface.minX...surface.maxX]
            world.updateSurfaces([surface], sampleInterval: frame)
            world.step(dt: frame, cursor: nil)
        }
        return surface
    }

    @Test("It snows")
    func spawnsFlakes() {
        var world = makeWorld()
        run(&world, seconds: 1)
        #expect(!world.flakes.isEmpty)
    }

    @Test("Snow settles on window tops")
    func settlesOnSurfaces() {
        let world = makeSnowyWorld()
        #expect(!world.hasNoSettledSnow)
    }

    @Test("Snow stays put when nothing changes")
    func stableSurfaceKeepsSnow() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)

        world.updateSurfaces([windowSurface], sampleInterval: frame)
        run(&world, seconds: 1)

        #expect(settledSnow(world) == before)
    }

    @Test("Snow rides along on a gently dragged window")
    func gentleDragKeepsSnow() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)

        let moved = drag(&world, speed: 60, seconds: 1)
        run(&world, seconds: 0.5)

        #expect(world.piles.first?.minX == moved.minX)
        #expect(settledSnow(world) > before * 0.9)
    }

    @Test("Yanking a window and stopping knocks the snow off")
    func yankShedsSnow() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)

        _ = drag(&world, speed: 1500, seconds: 0.3)
        run(&world, seconds: 0.2)

        #expect(settledSnow(world) < before * 0.3)
        #expect(world.isAnimatingQuickly)
    }

    @Test("A teleporting window drops its snow")
    func teleportShedsSnow() {
        var world = makeSnowyWorld()

        var moved = windowSurface
        moved.minX += 300
        moved.maxX += 300
        moved.visibleSpans = [moved.minX...moved.maxX]
        world.updateSurfaces([moved], sampleInterval: 0.25)
        run(&world, seconds: 0.2)

        #expect(world.hasNoSettledSnow)
    }

    @Test("Resizing a window jostles snow loose")
    func resizeShedsSnow() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)

        var resized = windowSurface
        resized.maxX -= 200
        resized.visibleSpans = [resized.minX...resized.maxX]
        world.updateSurfaces([resized], sampleInterval: frame)

        #expect(settledSnow(world) < before * 0.7)
    }

    @Test("Closing a window drops its snow")
    func vanishingSurfaceReleasesSnow() {
        var world = makeSnowyWorld()
        let flakesBefore = world.flakes.count

        world.updateSurfaces([], sampleInterval: frame)

        #expect(world.piles.isEmpty)
        #expect(world.flakes.count > flakesBefore)
    }

    @Test("Switching Spaces keeps the snow for when you come back")
    func hiddenWindowKeepsSnow() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)
        let flakesBefore = world.flakes.count

        world.updateSurfaces([], sampleInterval: frame, keeping: [windowSurface.id])
        #expect(world.flakes.count == flakesBefore)  // nothing fell

        world.updateSurfaces([windowSurface], sampleInterval: frame, keeping: [])
        #expect(settledSnow(world) == before)
    }

    @Test("A fast cursor brushes snow away, a resting cursor does not")
    func cursorBrushing() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)

        run(&world, seconds: 0.5, cursor: SIMD2(400, 396))
        #expect(settledSnow(world) == before)

        for step in 0..<30 {
            world.step(dt: frame, cursor: SIMD2(200 + Float(step) * 10, 396))
        }
        #expect(settledSnow(world) < before)
    }

    @Test("Particle count stays within the cap")
    func respectsCap() {
        var configuration = SnowConfiguration()
        configuration.maxFlakes = 300
        var world = SnowWorld(size: SIMD2(3000, 2000), configuration: configuration, seed: 1)
        world.intensity = 1
        world.prewarm()
        run(&world, seconds: 5)

        #expect(world.flakes.count <= 300)
    }
}
