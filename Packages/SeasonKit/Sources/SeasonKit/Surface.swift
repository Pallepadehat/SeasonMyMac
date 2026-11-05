/// Identifies something snow can settle on.
public enum SurfaceID: Hashable, Sendable {
    case window(UInt32)
    case dock
}

/// The top edge of a window (or the Dock), as seen from the sky.
///
/// Parts of the edge can be hidden behind other windows; snow only settles on
/// the ``visibleSpans``.
public struct Surface: Equatable, Sendable {
    public var id: SurfaceID
    public var minX: Float
    public var maxX: Float
    /// The y coordinate of the edge. Snow piles up above it (toward smaller y).
    public var y: Float
    public var visibleSpans: [ClosedRange<Float>]
    /// How tall snow can pile here. Lower than the global maximum when the
    /// edge sits right below the menu bar.
    public var maxPileHeight: Float

    public init(
        id: SurfaceID,
        minX: Float,
        maxX: Float,
        y: Float,
        visibleSpans: [ClosedRange<Float>],
        maxPileHeight: Float
    ) {
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.y = y
        self.visibleSpans = visibleSpans
        self.maxPileHeight = maxPileHeight
    }
}
