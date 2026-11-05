import Testing

@testable import SeasonKit

@Suite("Snow pile")
struct SnowPileTests {
    func makePile(spans: [ClosedRange<Float>] = [0...300], maxHeight: Float = 9) -> SnowPile {
        let surface = Surface(id: .window(1), minX: 0, maxX: 300, y: 100, visibleSpans: spans, maxPileHeight: maxHeight)
        return SnowPile(surface: surface, columnWidth: 3, maxSlope: 0.9)
    }

    @Test("Deposited snow raises the surface")
    func deposit() {
        var pile = makePile()
        _ = pile.deposit(1, atColumn: 50)

        #expect(pile.heights[50] > 0)
        #expect(pile.top(ofColumn: 50) < 100)
    }

    @Test("Snow slides until no slope is steeper than the limit")
    func angleOfRepose() {
        var pile = makePile()
        for _ in 0..<200 {
            _ = pile.deposit(1, atColumn: 50)
        }

        for column in 1..<pile.columnCount {
            #expect(abs(pile.heights[column] - pile.heights[column - 1]) <= 0.9 + 0.001)
        }
    }

    @Test("Piles never exceed their maximum height")
    func maxHeight() {
        var pile = makePile(maxHeight: 4)
        for column in 0..<pile.columnCount {
            for _ in 0..<20 { _ = pile.deposit(2, atColumn: column) }
        }
        #expect(pile.heights.allSatisfy { $0 <= 4 })
    }

    @Test("Snow slides off the end of a surface")
    func spillsAtEdges() {
        var pile = makePile()
        var spills: [SnowPile.Spill] = []
        for _ in 0..<20 {
            spills += pile.deposit(2, atColumn: 0)
        }
        #expect(!spills.isEmpty)
    }

    @Test("Covering part of a pile releases the snow underneath")
    func hidingColumnsReleasesSnow() {
        var pile = makePile()
        for column in 0..<pile.columnCount {
            _ = pile.deposit(1, atColumn: column)
        }

        let released = pile.updateVisibility([0...150])

        #expect(!released.isEmpty)
        #expect(released.allSatisfy { $0.x > 150 })
        #expect(pile.heights[60] == 0)
    }

    @Test("Brushing removes only the snow near the cursor")
    func brushing() {
        var pile = makePile()
        for column in 0..<pile.columnCount {
            _ = pile.deposit(1, atColumn: column)
        }

        let released = pile.removeSnow(near: SIMD2(150, 99), radius: 10)

        #expect(!released.isEmpty)
        #expect(released.allSatisfy { abs($0.x - 150) <= 12 })
        #expect(pile.heights[10] > 0)
    }
}
