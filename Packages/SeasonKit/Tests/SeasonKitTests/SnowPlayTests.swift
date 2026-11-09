import Testing

@testable import SeasonKit

@Suite("Playing in the snow")
struct SnowPlayTests {
    let frame: Float = 1.0 / 60
    let windowSurface = Surface(id: .window(7), minX: 100, maxX: 700, y: 400, visibleSpans: [100...700], maxPileHeight: 9)

    /// A world with a snowy window and no snow falling.
    func makeSnowyWorld() -> SnowWorld {
        var world = SnowWorld(size: SIMD2(800, 600), seed: 7)
        world.intensity = 1
        world.updateSurfaces([windowSurface], sampleInterval: frame)
        run(&world, seconds: 40)
        world.intensity = 0
        run(&world, seconds: 20)
        return world
    }

    func run(_ world: inout SnowWorld, seconds: Float) {
        for _ in 0..<Int(seconds * 60) {
            world.step(dt: frame, cursor: nil)
        }
    }

    func settledSnow(_ world: SnowWorld) -> Float {
        world.piles.reduce(0) { $0 + $1.totalSnow }
    }

    @Test("Scooping snow off a window makes a snowball and leaves less snow behind")
    func scoop() {
        var world = makeSnowyWorld()
        let before = settledSnow(world)
        let top = world.piles[0].snowTop(at: 400)!

        world.grab(at: SIMD2(400, top + 2))

        #expect(world.isHolding)
        #expect(world.snowballs.count == 1)
        #expect(world.snowballs[0].radius > world.play.minRadius)
        #expect(settledSnow(world) < before)
    }

    @Test("Rolling a snowball along a drift makes it bigger")
    func rolling() {
        var world = makeSnowyWorld()
        let top = world.piles[0].snowTop(at: 150)!
        world.grab(at: SIMD2(150, top))
        let startRadius = world.snowballs[0].radius

        for step in 0..<120 {
            world.moveHeld(to: SIMD2(150 + Float(step) * 4, top))
            world.step(dt: frame, cursor: nil)
        }

        #expect(world.snowballs[0].radius > startRadius + 3)
    }

    @Test("A dropped snowball comes to rest on the window below")
    func resting() {
        var world = makeSnowyWorld()
        world.grab(at: SIMD2(300, 100))
        world.release(velocity: .zero)
        run(&world, seconds: 3)

        let ball = world.snowballs[0]
        #expect(ball.state == .resting)
        #expect(abs(ball.position.y + ball.radius * 0.9 - world.piles[0].snowTop(at: ball.position.x)!) < 1)
    }

    @Test("A snowball rides along when its window moves gently")
    func ridesAlong() {
        var world = makeSnowyWorld()
        world.grab(at: SIMD2(300, 100))
        world.release(velocity: .zero)
        run(&world, seconds: 3)
        let startX = world.snowballs[0].position.x

        var surface = windowSurface
        for _ in 0..<60 {
            surface.minX += 1
            surface.maxX += 1
            surface.visibleSpans = [surface.minX...surface.maxX]
            world.updateSurfaces([surface], sampleInterval: frame)
            world.step(dt: frame, cursor: nil)
        }

        #expect(world.snowballs[0].state == .resting)
        #expect(abs(world.snowballs[0].position.x - (startX + 60)) < 2)
    }

    @Test("A snowball thrown hard at the edge of the screen splats")
    func splat() {
        var world = makeSnowyWorld()
        world.grab(at: SIMD2(400, 100))
        world.release(velocity: SIMD2(2500, -100))
        run(&world, seconds: 1)

        #expect(world.snowballs.isEmpty)
        #expect(!world.splats.isEmpty)
    }

    @Test("Without splats, a snowball bounces off the edge instead")
    func noSplat() {
        var world = makeSnowyWorld()
        world.play.splatsEnabled = false
        world.grab(at: SIMD2(400, 100))
        world.release(velocity: SIMD2(2500, -100))
        run(&world, seconds: 1)

        #expect(world.snowballs.count == 1)
        #expect(world.splats.isEmpty)
    }

    @Test("Stacking three snowballs builds a snowman")
    func stacking() {
        var world = makeSnowyWorld()
        for (radius, height) in [(Float(24), Float(150)), (17, 120), (12, 90)] {
            world.grab(at: SIMD2(400, height))
            world.snowballs[world.snowballs.count - 1].radius = radius
            world.release(velocity: .zero)
            run(&world, seconds: 2)
        }

        #expect(world.snowmen.count == 1)
        #expect(world.snowmen.first?.isComplete == true)
        #expect(world.snowballs.isEmpty)
    }

    @Test("A snowman can be carried to another window, in one piece")
    func carrySnowman() {
        var world = makeSnowyWorld()
        let other = Surface(id: .window(8), minX: 100, maxX: 300, y: 200, visibleSpans: [100...300], maxPileHeight: 9)
        world.updateSurfaces([windowSurface, other], sampleInterval: frame)
        world.buildSnowman(at: 600)
        run(&world, seconds: 4)
        let middle = world.snowmen[0].centers[1]

        world.grab(at: middle)
        #expect(world.isHolding)
        for step in 0..<90 {
            let t = Float(step) / 90
            world.moveHeld(to: middle + (SIMD2(200, 120) - middle) * t)
            world.step(dt: frame, cursor: nil)
        }
        world.release(velocity: .zero)
        run(&world, seconds: 3)

        #expect(world.snowmen.count == 1)
        #expect(world.snowmen[0].isComplete)
        #expect(abs(world.snowmen[0].base.y - other.y) < 12)
    }

    @Test("Grabbing with the top-ball option takes the head off instead")
    func takeHead() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 400)
        run(&world, seconds: 4)
        world.grab(at: world.snowmen[0].centers[2], takingTopBall: true)

        #expect(world.snowmen[0].radii.count == 2)
        #expect(world.snowballs.count == 1)
    }

    @Test("Melting a snowman shrinks it head first and leaves a puddle")
    func melting() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 400)
        run(&world, seconds: 4)
        let melted = world.meltSnowman(at: world.snowmen[0].centers[1])
        #expect(melted)

        run(&world, seconds: 0.4)
        let radii = world.snowmen[0].displayRadii
        #expect(radii[2] / world.snowmen[0].radii[2] < radii[0] / world.snowmen[0].radii[0])

        run(&world, seconds: 1.2)
        #expect(world.snowmen.isEmpty)
        #expect(!world.splats.isEmpty)
    }

    @Test("Melting everything melts snowballs too")
    func meltEverything() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 300)
        world.grab(at: SIMD2(600, 100))
        world.release(velocity: .zero)
        run(&world, seconds: 4)
        world.meltEverything()
        run(&world, seconds: 2)

        #expect(world.snowmen.isEmpty)
        #expect(world.snowballs.isEmpty)
    }

    @Test("Shaking off all snow topples snowmen")
    func shakeOffTopples() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 400)
        run(&world, seconds: 4)
        #expect(world.snowmen.count == 1)

        for _ in 0..<3 {
            world.shakeOffAllSnow()
            run(&world, seconds: 0.2)
        }
        run(&world, seconds: 3)
        #expect(world.snowmen.isEmpty)
    }

    @Test("A snowman built from the sky lands on a window")
    func buildSnowman() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 400)
        run(&world, seconds: 4)

        let snowman = world.snowmen[0]
        #expect(!snowman.isFalling)
        #expect(abs(snowman.base.y - windowSurface.y) < 12)
    }

    @Test("Snowmen on a window that moves to another Space come back with it")
    func stashing() {
        var world = makeSnowyWorld()
        world.buildSnowman(at: 400)
        run(&world, seconds: 4)

        world.updateSurfaces([], sampleInterval: frame, keeping: [.window(7)])
        run(&world, seconds: 1)
        #expect(world.snowmen.isEmpty)

        world.updateSurfaces([windowSurface], sampleInterval: frame)
        run(&world, seconds: 0.5)
        #expect(world.snowmen.count == 1)
    }

    @Test("Opening a present sets off sparkles")
    func openGift() {
        var world = makeSnowyWorld()
        world.dropGift(at: SIMD2(400, 100), velocity: .zero, style: 0)
        run(&world, seconds: 3)
        let gift = world.snowballs[0]
        #expect(gift.state == .resting)

        let opened = world.openGift(at: gift.position) != nil
        #expect(opened)
        #expect(world.snowballs.isEmpty)
        #expect(!world.sparkles.isEmpty)
    }

    @Test("The sleigh crosses the screen and drops its presents")
    func sleigh() {
        var sleigh = Sleigh(seed: 3)
        let size = SIMD2<Float>(1200, 800)
        sleigh.start(size: size, topInset: 24, gifts: 2)
        var gifts = 0
        for _ in 0..<(60 * 12) {
            for event in sleigh.step(dt: frame, size: size) {
                if case .dropGift = event { gifts += 1 }
            }
        }
        #expect(!sleigh.isFlying)
        #expect(gifts == 2)
    }
}
