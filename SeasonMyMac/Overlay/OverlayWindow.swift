import AppKit

/// A transparent, click-through window that covers one screen.
///
/// It sits above regular windows and the Dock, can't become key, shows on
/// every Space, and never steals focus or clicks.
final class OverlayWindow: NSWindow {
    let seasonView: SeasonView

    init(screen: NSScreen, seasonView: SeasonView, showsOverFullScreenApps: Bool) {
        self.seasonView = seasonView
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Above the Dock (which sits at the Dock level) so snow can rest on it.
        level = .statusBar
        setShowsOverFullScreenApps(showsOverFullScreenApps)

        contentView = seasonView
        setFrame(screen.frame, display: false)
    }

    /// Full-screen apps live on their own Spaces. Leaving out
    /// `.fullScreenAuxiliary` lets macOS itself keep the overlay off them.
    func setShowsOverFullScreenApps(_ shows: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if shows {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
