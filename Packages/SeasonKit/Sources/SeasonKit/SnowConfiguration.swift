/// Tunable constants for the snow simulation.
///
/// All distances are in points, all times in seconds. The coordinate system
/// has its origin in the top-left corner of the screen with y growing downward.
public struct SnowConfiguration: Sendable, Equatable {
    // MARK: Falling snow

    /// Flakes spawned per second for every 1000 pt of screen width at full intensity.
    public var flakesPerSecondPer1000Points: Float = 70

    /// Smallest and largest flake radius, before ``flakeSizeScale``.
    public var flakeRadius: ClosedRange<Float> = 0.8...3.2

    /// Multiplies every flake's size.
    public var flakeSizeScale: Float = 1

    /// Terminal fall speed for the farthest and nearest flakes, before ``fallSpeedScale``.
    public var fallSpeed: ClosedRange<Float> = 22...65

    /// Multiplies every flake's fall speed.
    public var fallSpeedScale: Float = 1

    /// Peak sideways drift caused by the flake fluttering.
    public var swaySpeed: Float = 14

    /// Strength of the wind, in points per second.
    public var windSpeed: Float = 18

    /// Prevailing wind direction: -1 blows left, 0 is gusty but calm on
    /// average, 1 blows right.
    public var windBias: Float = 0

    /// Flakes with a depth below this value are "far away" and never settle,
    /// which sells the illusion of depth.
    public var backgroundDepth: Float = 0.4

    /// Hard cap on simulated particles (flakes, clumps and powder).
    public var maxFlakes: Int = 5000

    // MARK: Settled snow

    /// Width of one column in a snow pile height map.
    public var columnWidth: Float = 3

    /// Tallest a drift can grow. Individual drifts vary between roughly 65% and
    /// 100% of this so the top of a pile looks natural.
    public var maxPileHeight: Float = 9

    /// Largest height difference between neighbouring columns before snow
    /// slides sideways (the "angle of repose").
    public var maxColumnSlope: Float = 1.4

    /// How much pile height a landed flake adds, relative to its area.
    public var settleFactor: Float = 0.22

    /// Multiplies how fast snow builds up.
    public var accumulationRate: Float = 1

    // MARK: Knocked-off snow

    /// How firmly settled snow holds on when a window moves, from 0 (slides
    /// off at the slightest nudge) to 1 (only a hard shake knocks it loose).
    public var stickiness: Float = 0.5

    /// The fraction of each column knocked loose per resize step.
    public var resizeShedFraction: Float = 0.15

    /// Downward acceleration of clumps.
    public var gravity: Float = 900

    /// Maximum fall speed of clumps.
    public var clumpTerminalSpeed: Float = 520

    /// Settled area (pt²) carried by one clump.
    public var clumpArea: Float = 10

    /// Settled area (pt²) carried by one bit of powder.
    public var powderArea: Float = 4

    /// Share of knocked-off snow that turns into slowly drifting powder
    /// rather than falling clumps.
    public var powderFraction: Float = 0.4

    /// Knocked-off snow can't settle again for this long, so it clears the
    /// surface it fell off.
    public var resettleDelay: Float = 0.6

    // MARK: Cursor

    public var cursorBrushesSnow = true

    /// The cursor has to move at least this fast to brush snow off.
    public var brushMinimumSpeed: Float = 110

    /// Radius around the cursor that brushes snow away.
    public var brushRadius: Float = 14

    public init() {}

    // MARK: Derived values

    /// A change in a surface's velocity smaller than this doesn't shake any snow loose.
    var shakeThreshold: Float { 40 + 360 * stickiness }

    /// How much more velocity change it takes to knock *all* the snow loose.
    var shakeRange: Float { 250 + 1250 * stickiness }
}
