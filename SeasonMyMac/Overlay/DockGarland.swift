import CoreGraphics

/// Works out where the string of lights is clipped onto the Dock, for each
/// ``DockLightStyle``. Shared by the desktop and the preview in Settings.
enum DockGarland {
    struct Layout {
        var anchors: [SIMD2<Float>]
        var sag: Float
        var bulbSpacing: Float
        var standsUpright: Bool
    }

    /// - Parameters:
    ///   - frame: The Dock, in top-left-origin points.
    ///   - items: The icons' frames, left to right, in the same space.
    ///   - density: The user's bulb density multiplier.
    static func layout(style: DockLightStyle, frame: CGRect, items: [CGRect], density: Double) -> Layout {
        switch style {
        case .rim: rim(frame: frame, density: Float(density))
        case .draped: draped(frame: frame, items: items, density: Float(density))
        }
    }

    /// Along the rounded rim of the Dock's glass: up the left side, across the
    /// top and down the right, with one upright bulb per clip.
    private static func rim(frame: CGRect, density: Float) -> Layout {
        let minX = Float(frame.minX.rounded()), maxX = Float(frame.maxX.rounded())
        let minY = Float(frame.minY.rounded()) - 0.5
        let height = Float(frame.height)
        let radius = min(height * 0.32, 34)
        let sideDrop = radius * 0.55

        // The outline as a fine polyline, then clips spread evenly along it.
        var outline: [SIMD2<Float>] = [SIMD2(minX, minY + radius + sideDrop)]
        func arc(center: SIMD2<Float>, from start: Float, to end: Float) {
            for step in 0...8 {
                let angle = start + (end - start) * Float(step) / 8
                outline.append(center + SIMD2(cos(angle), sin(angle)) * radius)
            }
        }
        arc(center: SIMD2(minX + radius, minY + radius), from: .pi, to: 1.5 * .pi)
        arc(center: SIMD2(maxX - radius, minY + radius), from: 1.5 * .pi, to: 2 * .pi)
        outline.append(SIMD2(maxX, minY + radius + sideDrop))

        let spacing = 22 / max(density, 0.3)
        let anchors = resample(outline, spacing: spacing)
        return Layout(anchors: anchors, sag: 1.2, bulbSpacing: spacing * 1.2, standsUpright: true)
    }

    /// Clipped above the middle of every icon, drooping so a bulb hangs in
    /// each gap between them rather than in front of an icon.
    private static func draped(frame: CGRect, items: [CGRect], density: Float) -> Layout {
        let y = Float(frame.minY.rounded()) + 1.5
        let iconWidth = Float(items.first?.width ?? 48)
        var xs: [Float]
        if items.count >= 2 {
            // From the middle of the first icon to the middle of the last, so
            // every bulb hangs in a gap.
            xs = items.map { Float($0.midX.rounded()) }
        } else {
            let count = max(2, Int(frame.width / 56))
            xs = (0...count).map { Float(frame.minX) + 14 + Float(frame.width - 28) * Float($0) / Float(count) }
        }
        let span = xs.count >= 2 ? (xs[xs.count - 1] - xs[0]) / Float(xs.count - 1) : iconWidth
        let perSpan = max(1, density.rounded())
        return Layout(anchors: xs.map { SIMD2($0, y) }, sag: max(4, iconWidth * 0.14), bulbSpacing: span / perSpan, standsUpright: false)
    }

    /// Points spaced `spacing` apart along a polyline.
    private static func resample(_ points: [SIMD2<Float>], spacing: Float) -> [SIMD2<Float>] {
        guard let first = points.first else { return [] }
        var lengths: [Float] = [0]
        for (a, b) in zip(points, points.dropFirst()) {
            let delta = b - a
            lengths.append(lengths[lengths.count - 1] + (delta * delta).sum().squareRoot())
        }
        let total = lengths[lengths.count - 1]
        let count = max(2, Int((total / spacing).rounded()))
        var result: [SIMD2<Float>] = [first]
        var segment = 0
        for index in 1...count {
            let target = total * Float(index) / Float(count)
            while segment < points.count - 2, lengths[segment + 1] < target { segment += 1 }
            let segmentLength = max(lengths[segment + 1] - lengths[segment], 0.0001)
            let t = (target - lengths[segment]) / segmentLength
            let point = points[segment] + (points[segment + 1] - points[segment]) * t
            result.append(point)
        }
        return result
    }
}
