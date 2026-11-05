import Testing

@testable import SeasonKit

@Suite("Light string")
struct LightStringTests {
    func makeString() -> LightString {
        var lights = LightString()
        lights.hang(between: [SIMD2(0, 100), SIMD2(200, 100), SIMD2(400, 100)], sag: 20, bulbSpacing: 40)
        return lights
    }

    @Test("Bulbs are spread along every span")
    func bulbLayout() {
        let lights = makeString()
        #expect(lights.bulbs.count == 10)
        #expect(lights.bulbs.allSatisfy { $0.anchor.x > 0 && $0.anchor.x < 400 })
    }

    @Test("The wire droops between anchors")
    func sag() {
        let middle = LightString.point(from: SIMD2(0, 100), to: SIMD2(200, 100), sag: 20, at: 0.5)
        #expect(middle == SIMD2(100, 120))
    }

    @Test("Colours cycle through the palette")
    func colors() {
        var lights = makeString()
        lights.palette = .candyCane
        #expect(lights.bulbs[0].color == LightPalette.candyCane.colors[0])
        #expect(lights.bulbs[1].color == LightPalette.candyCane.colors[1])
        #expect(lights.bulbs[2].color == LightPalette.candyCane.colors[0])
    }

    @Test("Touching a bulb makes it swing, then it settles")
    func swinging() {
        var lights = makeString()
        lights.animation = .steady
        let bulb = lights.bulbs[0].anchor + SIMD2(0, 8)

        lights.step(dt: 1.0 / 60, time: 0, wind: 0, cursor: bulb, cursorVelocity: SIMD2(800, 0))
        #expect(!lights.isAtRest)

        for frame in 0..<600 {
            lights.step(dt: 1.0 / 60, time: Float(frame) / 60, wind: 0, cursor: nil, cursorVelocity: .zero)
        }
        #expect(lights.isAtRest)
    }

    @Test("Re-hanging the same layout keeps the bulbs")
    func stableLayout() {
        var lights = makeString()
        lights.step(dt: 1.0 / 60, time: 0, wind: 0, cursor: lights.bulbs[0].anchor + SIMD2(0, 8), cursorVelocity: SIMD2(800, 0))
        let velocity = lights.bulbs[0].angularVelocity

        lights.hang(between: [SIMD2(0, 100), SIMD2(200, 100), SIMD2(400, 100)], sag: 20, bulbSpacing: 40)

        #expect(lights.bulbs[0].angularVelocity == velocity)
    }

    @Test("Moving the anchors glides the string instead of jumping")
    func glidesToNewAnchors() {
        var lights = makeString()
        let colors = lights.bulbs.map(\.color)
        let start = lights.bulbs[0].anchor

        lights.hang(between: [SIMD2(20, 100), SIMD2(220, 100), SIMD2(420, 100)], sag: 20, bulbSpacing: 40)
        lights.step(dt: 1.0 / 60, time: 0, wind: 0, cursor: nil, cursorVelocity: .zero)
        let firstFrame = lights.bulbs[0].anchor.x - start.x
        #expect(firstFrame > 0 && firstFrame < 5)  // moving, but not teleporting

        for frame in 1..<120 {
            lights.step(dt: 1.0 / 60, time: Float(frame) / 60, wind: 0, cursor: nil, cursorVelocity: .zero)
        }
        #expect(abs(lights.bulbs[0].anchor.x - start.x - 20) < 0.1)
        #expect(lights.bulbs.map(\.color) == colors)
    }
}
