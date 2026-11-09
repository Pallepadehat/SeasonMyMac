/// Snow resting on one surface, stored as a height map of narrow columns.
///
/// Column `i` covers `minX + i * columnWidth ..< minX + (i + 1) * columnWidth`.
/// Snow slides to a lower neighbour when the slope gets too steep, and slides
/// off the ends (or into hidden columns) as ``Spill``s. The pile also tracks
/// how its surface moves, so the world can shake snow loose.
public struct SnowPile: Sendable {
    /// Snow that left the pile, ready to become falling clumps and powder.
    struct ReleasedSnow: Equatable {
        var x: Float
        var width: Float
        var top: Float
        var bottom: Float

        var area: Float { (bottom - top) * width }
    }

    /// Snow that slid off the side of the pile.
    struct Spill: Equatable {
        var x: Float
        var y: Float
        var amount: Float
    }

    public let surfaceID: SurfaceID
    public private(set) var minX: Float
    public private(set) var maxX: Float
    /// The y coordinate of the surface the snow rests on.
    public private(set) var y: Float
    public let columnWidth: Float

    public private(set) var heights: [Float]
    public private(set) var isVisible: [Bool]

    /// How tall each column may grow. Varies along the pile so a full pile
    /// looks like rolling drifts rather than a flat slab.
    private var capacities: [Float]
    private var maxHeight: Float
    private let maxSlope: Float
    private let driftSeed: UInt64

    /// Smoothed velocity of the surface, in points per second.
    var velocity: SIMD2<Float> = .zero
    /// World time when the surface last moved.
    var lastMotionTime: Float = -.infinity

    init(surface: Surface, columnWidth: Float, maxSlope: Float) {
        surfaceID = surface.id
        minX = surface.minX
        maxX = surface.maxX
        y = surface.y
        maxHeight = surface.maxPileHeight
        self.columnWidth = columnWidth
        self.maxSlope = maxSlope
        driftSeed = Self.seed(for: surface.id)

        let count = Self.columnCount(for: surface, columnWidth: columnWidth)
        heights = Array(repeating: 0, count: count)
        isVisible = Array(repeating: false, count: count)
        capacities = []
        rebuildCapacities()
        _ = updateVisibility(surface.visibleSpans)
    }

    // MARK: Geometry

    public var columnCount: Int { heights.count }

    public func columnCenter(_ column: Int) -> Float {
        minX + (Float(column) + 0.5) * columnWidth
    }

    /// The y coordinate of the top of the snow in `column`.
    public func top(ofColumn column: Int) -> Float {
        y - heights[column]
    }

    /// The height of `column` softened by its neighbours, for drawing.
    ///
    /// Hidden columns and the space past either end count as zero, which
    /// gives every drift a rounded edge.
    public func displayHeight(ofColumn column: Int) -> Float {
        let weights: [Float] = [1, 4, 6, 4, 1]
        var total: Float = 0
        for (offset, weight) in zip(-2...2, weights) {
            let index = column + offset
            guard heights.indices.contains(index), isVisible[index] else { continue }
            total += heights[index] * weight
        }
        return total / 16
    }

    /// The column under `x`, if `x` lies on this pile.
    func column(at x: Float) -> Int? {
        guard x >= minX, x < maxX else { return nil }
        return min(Int((x - minX) / columnWidth), columnCount - 1)
    }

    func hasSameGeometry(as surface: Surface) -> Bool {
        abs(surface.minX - minX) < 0.5 && abs(surface.maxX - maxX) < 0.5 && abs(surface.y - y) < 0.5
    }

    func hasSameWidth(as surface: Surface) -> Bool {
        abs((surface.maxX - surface.minX) - (maxX - minX)) < 1
    }

    var isEmpty: Bool { !heights.contains { $0 > 0 } }

    var totalSnow: Float { heights.reduce(0, +) * columnWidth }

    // MARK: Moving

    /// Moves the pile along with its surface, keeping the snow on it.
    mutating func move(to surface: Surface) {
        minX = surface.minX
        maxX = surface.maxX
        y = surface.y
        maxHeight = surface.maxPileHeight

        let count = Self.columnCount(for: surface, columnWidth: columnWidth)
        if count != columnCount {
            heights = (0..<count).map { $0 < heights.count ? heights[$0] : 0 }
            isVisible = (0..<count).map { $0 < isVisible.count ? isVisible[$0] : false }
        }
        rebuildCapacities()
        clampToCapacity()
    }

    /// Fits the pile to a resized surface. Snow stays where it is on screen;
    /// whatever no longer has anything underneath falls off.
    mutating func resize(to surface: Surface) -> [ReleasedSnow] {
        let old = self
        self = SnowPile(surface: surface, columnWidth: columnWidth, maxSlope: maxSlope)

        var released: [ReleasedSnow] = []
        for column in old.heights.indices where old.heights[column] > 0.05 {
            let x = old.columnCenter(column)
            if let target = self.column(at: x), abs(old.y - y) < 0.5 {
                heights[target] = old.heights[column]
            } else {
                released.append(old.snow(inColumn: column, from: 0, to: old.heights[column]))
            }
        }
        clampToCapacity()
        return released
    }

    // MARK: Adding snow

    /// Adds snow centred on `column`, spread over its neighbours for a smooth look.
    /// Returns any snow that slid off the pile as a result.
    mutating func deposit(_ amount: Float, atColumn column: Int) -> [Spill] {
        let kernel: [(offset: Int, weight: Float)] = [(-2, 0.1), (-1, 0.2), (0, 0.4), (1, 0.2), (2, 0.1)]
        for (offset, weight) in kernel {
            let index = column + offset
            guard heights.indices.contains(index), isVisible[index] else { continue }
            heights[index] = min(capacities[index], heights[index] + amount * weight)
        }
        return settle(around: column)
    }

    /// Lets snow slide downhill around `center` until slopes are gentle again.
    ///
    /// Only the neighbourhood of the change is touched, so this stays cheap no
    /// matter how wide the pile is.
    private mutating func settle(around center: Int) -> [Spill] {
        var spills: [Spill] = []
        var lower = max(0, center - 3)
        var upper = min(columnCount - 1, center + 3)

        for _ in 0..<12 {
            var moved = false
            for index in lower...upper where isVisible[index] && heights[index] > 0 {
                for neighbour in [index - 1, index + 1] {
                    let isOpen = heights.indices.contains(neighbour) && isVisible[neighbour]
                    let neighbourHeight = isOpen ? heights[neighbour] : 0
                    let excess = heights[index] - neighbourHeight - maxSlope
                    guard excess > 0 else { continue }

                    let transfer = isOpen ? excess / 2 : excess
                    heights[index] -= transfer
                    moved = true

                    if isOpen {
                        heights[neighbour] = min(capacities[neighbour], heights[neighbour] + transfer)
                        lower = max(0, min(lower, neighbour - 1))
                        upper = min(columnCount - 1, max(upper, neighbour + 1))
                    } else {
                        let side: Float = neighbour < index ? -0.5 : 0.5
                        spills.append(Spill(x: columnCenter(index) + side * columnWidth, y: top(ofColumn: index), amount: transfer))
                    }
                }
            }
            if !moved { break }
        }
        return spills
    }

    // MARK: Removing snow

    /// Marks columns visible or hidden. Snow on newly hidden columns is released,
    /// because a window moved in front of it and pushed it off.
    mutating func updateVisibility(_ spans: [ClosedRange<Float>]) -> [ReleasedSnow] {
        var released: [ReleasedSnow] = []
        for column in heights.indices {
            let center = columnCenter(column)
            let visible = spans.contains { $0.contains(center) }
            if !visible, let removed = removeColumn(column) {
                released.append(removed)
            }
            isVisible[column] = visible
        }
        return released
    }

    /// Knocks the top `fraction` of every column loose.
    mutating func shed(fraction: Float) -> [ReleasedSnow] {
        guard fraction > 0 else { return [] }
        if fraction >= 1 { return removeAll() }

        var released: [ReleasedSnow] = []
        for column in heights.indices where heights[column] > 0.05 {
            let height = heights[column]
            let remaining = height * (1 - fraction)
            heights[column] = remaining
            released.append(snow(inColumn: column, from: remaining, to: height))
        }
        return released
    }

    /// Removes every bit of snow on the pile.
    mutating func removeAll() -> [ReleasedSnow] {
        heights.indices.compactMap { removeColumn($0) }
    }

    /// Removes snow within `radius` of `point`, as when the cursor brushes past.
    ///
    /// The cursor has to actually pass through the snow: moving along just
    /// below the surface (say, toward a Dock icon) leaves it alone.
    mutating func removeSnow(near point: SIMD2<Float>, radius: Float) -> [ReleasedSnow] {
        guard point.y <= y + 1, point.y >= y - maxHeight - radius else { return [] }
        guard
            let first = column(at: max(minX, point.x - radius)),
            let last = column(at: min(maxX - 0.001, point.x + radius))
        else { return [] }

        return (first...last).compactMap { column in
            guard point.y >= top(ofColumn: column) - radius else { return nil }
            return removeColumn(column)
        }
    }

    /// Takes up to `depth` points of snow off every visible column within
    /// `halfWidth` of `x`, the way a snowball rolling over them picks it up.
    ///
    /// - Returns: The area of snow taken, in pt².
    mutating func scoop(around x: Float, halfWidth: Float, depth: Float) -> Float {
        guard
            depth > 0,
            let first = column(at: max(minX, x - halfWidth)),
            let last = column(at: min(maxX - 0.001, x + halfWidth))
        else { return 0 }

        var area: Float = 0
        for column in first...last where isVisible[column] {
            let taken = min(heights[column], depth)
            heights[column] -= taken
            area += taken * columnWidth
        }
        return area
    }

    /// The y coordinate of the snow's top under `x`, or `nil` when `x` isn't on
    /// a visible part of this pile.
    func snowTop(at x: Float) -> Float? {
        guard let column = column(at: x), isVisible[column] else { return nil }
        return top(ofColumn: column)
    }

    private mutating func removeColumn(_ column: Int) -> ReleasedSnow? {
        let height = heights[column]
        heights[column] = 0
        guard height > 0.05 else { return nil }
        return snow(inColumn: column, from: 0, to: height)
    }

    /// The slice of `column` between two heights above the surface.
    private func snow(inColumn column: Int, from lowerHeight: Float, to upperHeight: Float) -> ReleasedSnow {
        ReleasedSnow(x: columnCenter(column), width: columnWidth, top: y - upperHeight, bottom: y - lowerHeight)
    }

    // MARK: Drifts

    private mutating func rebuildCapacities() {
        capacities = heights.indices.map { column in
            let position = Float(column)
            // Two layers of smooth noise: long rolling drifts plus small lumps.
            let drift = 0.7 * Self.smoothNoise(position / 14, seed: driftSeed) + 0.3 * Self.smoothNoise(position / 4, seed: driftSeed &+ 1)
            return maxHeight * (0.65 + 0.35 * drift)
        }
    }

    private mutating func clampToCapacity() {
        for column in heights.indices {
            heights[column] = min(heights[column], capacities[column])
        }
    }

    private static func columnCount(for surface: Surface, columnWidth: Float) -> Int {
        max(1, Int(((surface.maxX - surface.minX) / columnWidth).rounded(.up)))
    }

    private static func seed(for id: SurfaceID) -> UInt64 {
        switch id {
        case .window(let number): UInt64(number) &* 0x9E37_79B9
        case .dock: 0xD0C
        }
    }

    /// Smooth value noise in 0...1.
    private static func smoothNoise(_ position: Float, seed: UInt64) -> Float {
        let cell = position.rounded(.down)
        let fraction = position - cell
        let eased = fraction * fraction * (3 - 2 * fraction)
        let left = hash(Int(cell), seed: seed)
        let right = hash(Int(cell) + 1, seed: seed)
        return left + (right - left) * eased
    }

    private static func hash(_ value: Int, seed: UInt64) -> Float {
        var generator = SplitMix64(seed: seed ^ UInt64(bitPattern: Int64(value)) &* 0xBF58_476D_1CE4_E5B9)
        return Float(generator.next() >> 40) / Float(1 << 24)
    }
}
