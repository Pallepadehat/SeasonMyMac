// Small vector helpers shared by the simulations.

func length(_ vector: SIMD2<Float>) -> Float {
    (vector * vector).sum().squareRoot()
}

func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    length(a - b)
}

func clamped(_ vector: SIMD2<Float>, maxLength: Float) -> SIMD2<Float> {
    let currentLength = length(vector)
    guard currentLength > maxLength else { return vector }
    return vector * (maxLength / currentLength)
}

func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
