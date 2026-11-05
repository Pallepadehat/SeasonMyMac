import AppKit
import ApplicationServices

/// Works out which displays are showing a full-screen window right now.
///
/// It asks the most reliable source available:
/// 1. This app's own windows report full screen in their style mask.
/// 2. Other apps' windows report it through Accessibility (`AXFullScreen`),
///    when the user has granted access.
/// 3. Geometry: a window covering its display edge to edge (games and
///    presentations often do this without a full-screen Space). Without
///    Accessibility, a window spanning from just below the notch to the
///    bottom also counts.
///
/// Answers are in global (top-left origin) coordinates: the frames of the
/// displays that are full screen.
enum FullScreenDetector {
    static func fullScreenDisplays(windows: [DesktopWindow]) -> [CGRect] {
        let screens = NSScreen.screens.map { screen in
            (screen: screen, frame: ScreenGeometry(screen: screen).globalFrame)
        }

        let canAskAccessibility = AXIsProcessTrusted()
        var frames: [CGRect] = ownFullScreenWindowFrames()
        if canAskAccessibility, let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            frames += accessibilityFullScreenWindowFrames(of: frontmost.processIdentifier)
        }

        var displays: [CGRect] = []
        for (screen, screenFrame) in screens {
            let isFullScreen =
                frames.contains { $0.intersects(screenFrame) }
                || windows.contains { window in
                    // With Accessibility the exact answer is already in `frames`, so
                    // only the unambiguous edge-to-edge case is checked here.
                    let notchHeight = canAskAccessibility ? 0 : screen.safeAreaInsets.top
                    return looksFullScreen(window.frame, on: screenFrame, notchHeight: notchHeight)
                }
            if isFullScreen {
                displays.append(screenFrame)
            }
        }
        return displays
    }

    /// This app's own windows (such as Settings) that are in full screen.
    private static func ownFullScreenWindowFrames() -> [CGRect] {
        NSApplication.shared.windows
            .filter { $0.styleMask.contains(.fullScreen) && $0.isVisible && $0.isOnActiveSpace }
            .compactMap { window in window.screen.map { ScreenGeometry(screen: $0).globalFrame } }
    }

    /// Windows of `process` that Accessibility says are full screen.
    private static func accessibilityFullScreenWindowFrames(of process: pid_t) -> [CGRect] {
        let application = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(application, 0.1)
        let windows = application.attribute(kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.compactMap { window in
            guard (window.attribute("AXFullScreen") as? Bool) == true else { return nil }
            return window.frame
        }
    }

    /// Whether a window fills its display edge to edge, allowing for the
    /// strip a full-screen app leaves free beside the camera notch.
    private static func looksFullScreen(_ window: CGRect, on screen: CGRect, notchHeight: CGFloat) -> Bool {
        abs(window.minX - screen.minX) < 1
            && abs(window.width - screen.width) < 1
            && abs(window.maxY - screen.maxY) < 1
            && window.minY - screen.minY <= max(notchHeight, 0) + 1
            && (notchHeight > 0 || window.minY - screen.minY < 1)
    }
}
