import AppKit

/// Converts between the coordinate spaces involved in drawing on a screen.
///
/// - **Cocoa** (`NSScreen`, `NSEvent`): origin at the bottom-left of the main
///   display, y grows upward.
/// - **Global** (Core Graphics window list, Accessibility): origin at the
///   top-left of the main display, y grows downward.
/// - **Local**: the global space shifted so this screen's top-left is (0, 0).
///   The simulation and renderer both work in local space.
struct ScreenGeometry: Equatable {
    /// The screen's frame in global coordinates.
    let globalFrame: CGRect
    /// Height of the menu bar strip at the top of the screen (0 if hidden).
    let menuBarHeight: CGFloat
    /// The display with the menu bar and the Dock's default home.
    let isMainDisplay: Bool

    init(screen: NSScreen) {
        let frame = screen.frame
        globalFrame = CGRect(
            x: frame.minX,
            y: Self.mainDisplayHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        isMainDisplay = screen == NSScreen.screens.first
    }

    var size: SIMD2<Float> {
        SIMD2(Float(globalFrame.width), Float(globalFrame.height))
    }

    var localBounds: CGRect {
        CGRect(origin: .zero, size: globalFrame.size)
    }

    func localRect(fromGlobal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -globalFrame.minX, dy: -globalFrame.minY)
    }

    /// The point in local coordinates, or `nil` if it's on another screen.
    func localPoint(fromGlobal point: CGPoint) -> SIMD2<Float>? {
        guard globalFrame.contains(point) else { return nil }
        return SIMD2(Float(point.x - globalFrame.minX), Float(point.y - globalFrame.minY))
    }

    static func globalPoint(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    /// Global coordinates are anchored to the display that holds the menu bar,
    /// which is always the first entry in `NSScreen.screens`.
    private static var mainDisplayHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }
}
