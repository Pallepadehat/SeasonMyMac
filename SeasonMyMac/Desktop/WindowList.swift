import CoreGraphics
import Foundation

/// A regular app window that's currently visible.
struct DesktopWindow: Equatable {
    let id: CGWindowID
    let ownerProcess: pid_t
    /// Frame in global (top-left origin) coordinates.
    let frame: CGRect
}

/// Reads windows from the window server.
///
/// `CGWindowListCopyWindowInfo` returns window bounds without needing Screen
/// Recording permission. The entries are read as Foundation dictionaries
/// rather than bridged to Swift ones, which keeps this cheap enough to call
/// many times a second.
enum WindowList {
    /// Windows smaller than this (tooltips, tiny utility panels) are ignored.
    private static let minimumSize = CGSize(width: 80, height: 40)

    /// Visible app windows on the current Space, ordered front to back.
    static func onScreenWindows() -> [DesktopWindow] {
        appWindows(options: [.optionOnScreenOnly, .excludeDesktopElements]).compactMap { entry in
            guard
                ((entry[kCGWindowAlpha] as? NSNumber)?.doubleValue ?? 0) > 0.05,
                let id = (entry[kCGWindowNumber] as? NSNumber)?.uint32Value,
                let owner = (entry[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                let bounds = entry[kCGWindowBounds] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width >= minimumSize.width,
                frame.height >= minimumSize.height
            else { return nil }

            return DesktopWindow(id: id, ownerProcess: owner, frame: frame)
        }
    }

    /// IDs of every app window that exists, including ones on other Spaces,
    /// minimized, or belonging to hidden apps.
    static func existingWindowIDs() -> Set<CGWindowID> {
        Set(appWindows(options: .excludeDesktopElements).compactMap { ($0[kCGWindowNumber] as? NSNumber)?.uint32Value })
    }

    /// Layer-0 windows (regular app windows) not owned by this app.
    private static func appWindows(options: CGWindowListOption) -> [NSDictionary] {
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else { return [] }
        let ownProcess = ProcessInfo.processInfo.processIdentifier

        var windows: [NSDictionary] = []
        for case let entry as NSDictionary in entries {
            // Layer 0 holds normal app windows; menus, the Dock, and the menu bar sit higher.
            guard
                (entry[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                (entry[kCGWindowOwnerPID] as? NSNumber)?.int32Value != ownProcess
            else { continue }
            windows.append(entry)
        }
        return windows
    }
}
