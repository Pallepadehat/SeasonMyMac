import CoreGraphics

/// A rectangle on screen that can hide other surfaces and optionally hold snow.
public struct SurfaceSource: Sendable {
    public var id: SurfaceID
    /// Frame in screen-local, top-left-origin coordinates.
    public var frame: CGRect
    /// Whether snow may settle on this rectangle's top edge.
    public var acceptsSnow: Bool
    /// Horizontal inset of the snowy edge, e.g. to stay clear of rounded corners.
    public var edgeInset: CGFloat

    public init(id: SurfaceID, frame: CGRect, acceptsSnow: Bool, edgeInset: CGFloat = 0) {
        self.id = id
        self.frame = frame
        self.acceptsSnow = acceptsSnow
        self.edgeInset = edgeInset
    }
}

/// Turns a stack of on-screen rectangles into the surfaces snow can land on.
public enum SurfaceLayout {
    /// Builds snowy surfaces from rectangles ordered front to back.
    ///
    /// - Parameters:
    ///   - sources: Rectangles ordered from frontmost to backmost.
    ///   - bounds: The screen bounds in the same coordinate space.
    ///   - topInset: Height of the menu bar; snow never piles into it.
    ///   - maxPileHeight: Upper limit for pile height.
    ///   - minimumSpanWidth: Visible slivers narrower than this are ignored.
    public static func surfaces(
        from sources: [SurfaceSource],
        in bounds: CGRect,
        topInset: CGFloat,
        maxPileHeight: Float,
        minimumSpanWidth: Float = 6
    ) -> [Surface] {
        let ceiling = Float(bounds.minY + topInset)
        var surfaces: [Surface] = []

        for (index, source) in sources.enumerated() where source.acceptsSnow {
            let edgeY = Float(source.frame.minY)
            let clearance = edgeY - ceiling
            guard clearance >= 4, edgeY < Float(bounds.maxY) else { continue }

            let minX = Float(max(source.frame.minX + source.edgeInset, bounds.minX))
            let maxX = Float(min(source.frame.maxX - source.edgeInset, bounds.maxX))
            guard maxX - minX >= minimumSpanWidth else { continue }

            let pileHeight = min(maxPileHeight, clearance)
            var spans = [minX...maxX]

            // Anything in front that overlaps the band where snow would sit hides it.
            for occluder in sources[..<index] {
                let frame = occluder.frame
                let overlapsPile = Float(frame.minY) < edgeY && Float(frame.maxY) > edgeY - pileHeight
                guard overlapsPile else { continue }
                spans = subtract(Float(frame.minX)...Float(frame.maxX), from: spans)
            }

            spans.removeAll { $0.upperBound - $0.lowerBound < minimumSpanWidth }
            guard !spans.isEmpty else { continue }

            surfaces.append(
                Surface(
                    id: source.id,
                    minX: minX,
                    maxX: maxX,
                    y: edgeY,
                    visibleSpans: spans,
                    maxPileHeight: pileHeight
                )
            )
        }
        return surfaces
    }

    /// Removes `cut` from every span, splitting spans that it lands in the middle of.
    static func subtract(_ cut: ClosedRange<Float>, from spans: [ClosedRange<Float>]) -> [ClosedRange<Float>] {
        var result: [ClosedRange<Float>] = []
        for span in spans {
            guard cut.overlaps(span) else {
                result.append(span)
                continue
            }
            if span.lowerBound < cut.lowerBound {
                result.append(span.lowerBound...cut.lowerBound)
            }
            if cut.upperBound < span.upperBound {
                result.append(cut.upperBound...span.upperBound)
            }
        }
        return result
    }
}
