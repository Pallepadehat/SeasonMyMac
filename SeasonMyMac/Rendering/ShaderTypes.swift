/// GPU data layouts shared with `Scene.metal`.
///
/// Field order and types must match the Metal structs exactly. `SIMD2<Float>`
/// lines up with Metal's `float2` (8 bytes) and `SIMD4<Float>` with `float4`
/// (16 bytes, 16-byte aligned).

/// Per-frame constants.
struct SceneUniforms {
    /// Size of the drawing area in points.
    var viewportSize: SIMD2<Float>
}

/// One snowflake or clump, drawn as a soft dot.
struct FlakeInstance {
    var center: SIMD2<Float>
    var radius: Float
    var opacity: Float
}

/// The slice of a snow pile between two neighbouring column centres.
struct PileSegment {
    /// Left column centre: x and the y of the snow's top.
    var start: SIMD2<Float>
    /// Right column centre: x and the y of the snow's top.
    var end: SIMD2<Float>
    /// The y of the surface the snow rests on.
    var baseY: Float
    var opacity: Float
}

/// A straight piece of the wire that holds the lights.
struct WireSegment {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var width: Float
    /// 1 for the soft shadow drawn beneath the wire, 0 for the wire itself.
    var isShadow: Float = 0
}

/// One light bulb hanging from the wire.
struct BulbInstance {
    /// Where the bulb attaches to the wire.
    var anchor: SIMD2<Float>
    /// Swing angle in radians.
    var angle: Float
    /// Radius of the glass, in points.
    var size: Float
    /// Colour in `rgb`, brightness (0...1) in `w`.
    var color: SIMD4<Float>
}
