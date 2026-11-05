import CoreGraphics
import Testing

@testable import SeasonKit

@Suite("Surface layout")
struct SurfaceLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("A lone window gets its whole top edge")
    func singleWindow() {
        let surfaces = SurfaceLayout.surfaces(
            from: [SurfaceSource(id: .window(1), frame: CGRect(x: 100, y: 200, width: 300, height: 200), acceptsSnow: true)],
            in: screen, topInset: 30, maxPileHeight: 9
        )

        #expect(surfaces.count == 1)
        #expect(surfaces[0].y == 200)
        #expect(surfaces[0].visibleSpans == [100...400])
    }

    @Test("A window in front hides the part of the edge behind it")
    func occludedEdge() {
        let front = SurfaceSource(id: .window(1), frame: CGRect(x: 200, y: 150, width: 100, height: 300), acceptsSnow: true)
        let back = SurfaceSource(id: .window(2), frame: CGRect(x: 100, y: 200, width: 300, height: 200), acceptsSnow: true)

        let surfaces = SurfaceLayout.surfaces(from: [front, back], in: screen, topInset: 30, maxPileHeight: 9)
        let backSurface = surfaces.first { $0.id == .window(2) }

        #expect(backSurface?.visibleSpans == [100...200, 300...400])
    }

    @Test("Snow never piles up into the menu bar")
    func clearanceBelowMenuBar() {
        let maximized = SurfaceSource(id: .window(1), frame: CGRect(x: 0, y: 32, width: 1000, height: 700), acceptsSnow: true)
        let nearTop = SurfaceSource(id: .window(2), frame: CGRect(x: 0, y: 36, width: 500, height: 100), acceptsSnow: true)

        let surfaces = SurfaceLayout.surfaces(from: [nearTop, maximized], in: screen, topInset: 30, maxPileHeight: 9)

        #expect(surfaces.map(\.id) == [.window(2)])
        #expect(surfaces[0].maxPileHeight == 6)
    }

    @Test("Occluders that don't accept snow still hide edges")
    func nonSnowyOccluder() {
        let occluder = SurfaceSource(id: .dock, frame: CGRect(x: 0, y: 190, width: 1000, height: 50), acceptsSnow: false)
        let window = SurfaceSource(id: .window(2), frame: CGRect(x: 100, y: 200, width: 300, height: 200), acceptsSnow: true)

        let surfaces = SurfaceLayout.surfaces(from: [occluder, window], in: screen, topInset: 30, maxPileHeight: 9)

        #expect(surfaces.isEmpty)
    }

    @Test("Subtracting ranges splits and trims spans")
    func subtract() {
        #expect(SurfaceLayout.subtract(5...10, from: [0...20]) == [0...5, 10...20])
        #expect(SurfaceLayout.subtract(-5...5, from: [0...20]) == [5...20])
        #expect(SurfaceLayout.subtract(30...40, from: [0...20]) == [0...20])
        #expect(SurfaceLayout.subtract(0...20, from: [5...10]) == [])
    }
}
