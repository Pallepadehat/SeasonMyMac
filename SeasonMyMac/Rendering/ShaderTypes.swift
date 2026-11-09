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

/// A snowball, or (with `kind` 1) the splat a snowball leaves behind.
struct SnowballInstance {
    var center: SIMD2<Float>
    var radius: Float
    /// How far it has rolled, in radians; for a splat, the direction it faces.
    var rotation: Float
    var squash: Float
    var opacity: Float
    var seed: Float
    /// 0 for a snowball, 1 for a splat.
    var kind: Float
}

/// A snowman: up to three balls, a face, a hat, a scarf and stick arms.
struct SnowmanInstance {
    /// The bottom centre.
    var base: SIMD2<Float>
    var tilt: Float
    /// 0...1: how far the decorations have popped in.
    var decorations: Float
    /// Ball radii from the bottom up in `xyz`, the number of balls in `w`.
    var radii: SIMD4<Float>
    /// Scarf colour in `rgb`; `w` is 0 for no scarf.
    var scarf: SIMD4<Float>
    /// 0 none, 1 top hat, 2 Santa hat, 3 beanie.
    var hat: Float
    var arms: Float
    var nose: Float
    var opacity: Float
}

/// A glint of coloured light.
struct SparkleInstance {
    var center: SIMD2<Float>
    var size: Float
    var opacity: Float
    var color: SIMD4<Float>
}

/// A picture from the sprite atlas (a reindeer, the sleigh, a present).
struct SpriteInstance {
    var center: SIMD2<Float>
    var size: SIMD2<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
    var rotation: Float
    var opacity: Float
    /// 1 mirrors the picture horizontally.
    var flip: Float
    var padding: Float = 0
}

/// Frost growing in from one corner of the screen.
struct FrostInstance {
    /// The corner of the screen.
    var corner: SIMD2<Float>
    /// How far the frost reaches, signed toward the middle of the screen.
    var extent: SIMD2<Float>
    var amount: Float
    var seed: Float
    var time: Float
    var padding: Float = 0
}
