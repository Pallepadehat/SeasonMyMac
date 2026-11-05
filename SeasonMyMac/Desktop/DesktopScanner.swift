import AppKit
import SeasonKit

/// Watches the desktop (windows, the Dock, the frontmost app, the cursor) and
/// describes it to the simulation.
///
/// One scanner is shared by every screen. It caches what it reads so the
/// window server is asked as rarely as possible, no matter how many displays
/// are drawing.
final class DesktopScanner {
    /// How often windows are re-read while they're probably being dragged or
    /// resized (a mouse button is down). Snow rides along smoothly.
    private let activeWindowRefreshInterval: CFTimeInterval = 1.0 / 90

    /// How often windows are re-read otherwise. Reading the window list is the
    /// single most expensive thing the app does, so it's kept rare when idle.
    private let idleWindowRefreshInterval: CFTimeInterval = 1.0 / 4

    /// Keep polling quickly for a moment after any change, since one change
    /// (a window opening, an app switching) is often followed by more.
    private let activityGracePeriod: CFTimeInterval = 0.5

    /// Reading the Dock goes through Accessibility, so it's done sparingly.
    private let dockRefreshInterval: CFTimeInterval = 0.5

    /// Keeps snow clear of the rounded corners of windows and the Dock.
    private let cornerInset: CGFloat = 10

    let dockLocator = DockLocator()

    /// Per-app exceptions, keyed by bundle identifier.
    var appRules: [String: AppRule.Behavior] = [:] {
        didSet { generation += 1 }
    }

    /// Bumped every time the windows or the Dock change, so screens know when
    /// to rebuild their surfaces.
    private(set) var generation = 0

    /// Seconds between the two most recent window samples.
    private(set) var lastSampleInterval: Float = 1.0 / 60

    private(set) var dockLayout: DockLayout?

    /// Windows that are still open but out of sight (on another Space,
    /// minimized, or hidden). Their snow is kept for when they come back.
    private(set) var hiddenSurfaceIDs: Set<SurfaceID> = []

    /// Frames of the displays showing a full-screen window.
    private var fullScreenDisplays: [CGRect] = []
    private var lastFullScreenCheck: CFTimeInterval = -.infinity
    private var lastFrontmostProcess: pid_t?

    private var windows: [DesktopWindow] = []
    private var bundleIdentifiers: [pid_t: String] = [:]
    private var lastWindowRefresh: CFTimeInterval = -.infinity
    private var lastWindowChange: CFTimeInterval = -.infinity
    private var lastDockRefresh: CFTimeInterval = -.infinity

    // MARK: Refreshing

    /// Re-reads windows and the Dock if their cached values are stale.
    func refreshIfNeeded(at time: CFTimeInterval, includeDock: Bool) {
        let windowsChanged = refreshWindowsIfNeeded(at: time)
        refreshFullScreenIfNeeded(at: time, windowsChanged: windowsChanged)

        if time - lastDockRefresh >= dockRefreshInterval {
            lastDockRefresh = time
            let latest = includeDock ? dockLocator.layout() : nil
            if latest != dockLayout {
                dockLayout = latest
                generation += 1
            }
        }
    }

    /// Re-checks full screen when windows or the frontmost app changed, and a
    /// few times a second otherwise (a window can go full screen in place).
    private func refreshFullScreenIfNeeded(at time: CFTimeInterval, windowsChanged: Bool) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let isDue = windowsChanged || frontmost != lastFrontmostProcess || time - lastFullScreenCheck >= idleWindowRefreshInterval
        guard isDue else { return }
        lastFrontmostProcess = frontmost
        lastFullScreenCheck = time
        fullScreenDisplays = FullScreenDetector.fullScreenDisplays(windows: windows)
    }

    /// Returns `true` if the windows changed.
    private func refreshWindowsIfNeeded(at time: CFTimeInterval) -> Bool {
        let isMouseDown = NSEvent.pressedMouseButtons != 0
        let changedRecently = time - lastWindowChange < activityGracePeriod
        let interval = isMouseDown || changedRecently ? activeWindowRefreshInterval : idleWindowRefreshInterval
        guard time - lastWindowRefresh >= interval else { return false }

        lastSampleInterval = Float(min(time - lastWindowRefresh, 1))
        lastWindowRefresh = time

        let latest = WindowList.onScreenWindows()
        guard latest != windows else { return false }

        updateHiddenWindows(previous: windows, latest: latest)
        windows = latest
        lastWindowChange = time
        generation += 1
        return true
    }

    /// Works out which windows left the screen without closing.
    private func updateHiddenWindows(previous: [DesktopWindow], latest: [DesktopWindow]) {
        let visible = Set(latest.map(\.id))
        let vanished = previous.map(\.id).filter { !visible.contains($0) }
        let candidates = hiddenSurfaceIDs.union(vanished.map(SurfaceID.window))
        guard !candidates.isEmpty else { return }

        // Only ask for the full list when something actually disappeared.
        let existing = WindowList.existingWindowIDs()
        hiddenSurfaceIDs = candidates.filter { id in
            guard case .window(let number) = id else { return false }
            return existing.contains(number) && !visible.contains(number)
        }
    }

    // MARK: Questions

    /// The surfaces snow can settle on for one screen, in its local coordinates.
    func surfaces(on screen: ScreenGeometry, settings: SnowSettings, maxPileHeight: Float) -> [Surface] {
        var sources: [SurfaceSource] = []

        // The Dock floats above every window, so it goes first (frontmost).
        if let dockLayout, dockLayout.isHorizontal, settings.settlesOnDock {
            sources.append(
                SurfaceSource(
                    id: .dock,
                    frame: screen.localRect(fromGlobal: dockLayout.frame),
                    acceptsSnow: true,
                    edgeInset: cornerInset
                )
            )
        }

        // Windows always hide what's behind them, even if they don't collect snow.
        for window in windows {
            let isExcluded = rule(for: window) == .noSnowOnWindows
            sources.append(
                SurfaceSource(
                    id: .window(window.id),
                    frame: screen.localRect(fromGlobal: window.frame),
                    acceptsSnow: settings.settlesOnWindows && !isExcluded,
                    edgeInset: cornerInset
                )
            )
        }

        return SurfaceLayout.surfaces(
            from: sources,
            in: screen.localBounds,
            topInset: screen.menuBarHeight,
            maxPileHeight: maxPileHeight
        )
    }

    /// Whether the effects should step aside on `screen` right now: an app
    /// set to pause them is in front, or something is playing full screen.
    func shouldHideEffects(on screen: ScreenGeometry, visibility: VisibilitySettings) -> Bool {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            appRules[frontmost] == .pauseEffects
        {
            return true
        }

        if visibility.hidesInFullScreen {
            return fullScreenDisplays.contains { $0.intersects(screen.globalFrame.insetBy(dx: 1, dy: 1)) }
        }
        return false
    }

    /// The mouse position on `screen`, or `nil` if it's on a different screen.
    func cursorLocation(on screen: ScreenGeometry) -> SIMD2<Float>? {
        screen.localPoint(fromGlobal: ScreenGeometry.globalPoint(fromCocoa: NSEvent.mouseLocation))
    }

    private func rule(for window: DesktopWindow) -> AppRule.Behavior? {
        guard !appRules.isEmpty else { return nil }
        if bundleIdentifiers[window.ownerProcess] == nil {
            bundleIdentifiers[window.ownerProcess] = NSRunningApplication(processIdentifier: window.ownerProcess)?.bundleIdentifier ?? ""
        }
        return bundleIdentifiers[window.ownerProcess].flatMap { appRules[$0] }
    }
}
