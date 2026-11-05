import AppKit
import ApplicationServices

/// Where the Dock is and where its icons sit, in global coordinates.
struct DockLayout: Equatable {
    var frame: CGRect
    /// Frames of the individual icons, left to right.
    var itemFrames: [CGRect]
    /// `false` when the layout is estimated rather than read from the Dock.
    var isExact: Bool

    /// Snow and lights only make sense along a horizontal Dock.
    var isHorizontal: Bool { frame.width > frame.height }
}

/// Finds the Dock.
///
/// With Accessibility access the exact frame of the Dock and its icons is read
/// through the Accessibility API. Without it, the layout is estimated from the
/// Dock's preferences and the running apps, which is close but not perfect.
final class DockLocator {
    private var dockElement: AXUIElement?
    private var dockProcess: pid_t?
    private var cachedItems: (frame: CGRect, items: [CGRect])?

    /// Whether the user has granted Accessibility access.
    var isAccessGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads the user to the Accessibility settings.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func layout() -> DockLayout? {
        if isAccessGranted, let exact = exactLayout() {
            return exact
        }
        return Self.estimatedLayout()
    }

    // MARK: Accessibility

    private func exactLayout() -> DockLayout? {
        guard let dock = dockApplicationElement() else { return nil }

        let children = dock.attribute(kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard
            let shelf = children.first(where: { $0.attribute(kAXRoleAttribute) as? String == kAXListRole }),
            let frame = shelf.frame
        else { return nil }

        // Reading every icon costs a round trip each, so only re-read them when
        // the Dock itself changed size or position.
        if cachedItems?.frame != frame {
            let items = (shelf.attribute(kAXChildrenAttribute) as? [AXUIElement] ?? [])
                .compactMap(\.frame)
                .sorted { $0.minX < $1.minX }
            cachedItems = (frame, items)
        }
        return DockLayout(frame: frame, itemFrames: cachedItems?.items ?? [], isExact: true)
    }

    /// The Accessibility element for the Dock process, recreated if the Dock restarts.
    private func dockApplicationElement() -> AXUIElement? {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return nil
        }
        if process != dockProcess {
            let element = AXUIElementCreateApplication(process)
            // Never let a busy Dock stall the main thread for long.
            AXUIElementSetMessagingTimeout(element, 0.1)
            dockElement = element
            dockProcess = process
            cachedItems = nil
        }
        return dockElement
    }

    // MARK: Estimate

    /// Rebuilds the Dock's layout from its preferences: icon size, pinned
    /// apps and folders, recent apps, and whatever else is running.
    private static func estimatedLayout() -> DockLayout? {
        guard
            let preferences = UserDefaults(suiteName: "com.apple.dock"),
            let screen = NSScreen.screens.first
        else { return nil }

        let orientation = preferences.string(forKey: "orientation") ?? "bottom"
        let dockHeight = screen.visibleFrame.minY - screen.frame.minY
        guard orientation == "bottom", !preferences.bool(forKey: "autohide"), dockHeight > 20 else { return nil }

        let tileSize = CGFloat(preferences.object(forKey: "tilesize") as? Double ?? 48)
        let pinned = bundleIdentifiers(in: preferences.array(forKey: "persistent-apps"))
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != "com.apple.finder" && !pinned.contains($0) }
        let showsRecents = preferences.object(forKey: "show-recents") as? Bool ?? true
        let recents = showsRecents ? Array(bundleIdentifiers(in: preferences.array(forKey: "recent-apps")).prefix(3)) : []
        let unpinned = Set(running).union(recents)
        let folders = (preferences.array(forKey: "persistent-others")?.count ?? 0) + 1  // + Trash

        // Finder, pinned apps, running/recent apps, then folders and the Trash.
        let groups = [1 + pinned.count, unpinned.count, folders].filter { $0 > 0 }
        let separatorWidth = tileSize * 0.4
        let padding = tileSize * 0.25
        let iconCount = groups.reduce(0, +)
        let width = CGFloat(iconCount) * tileSize + CGFloat(groups.count - 1) * separatorWidth + 2 * padding
        let height = dockHeight - 6

        // Global coordinates: y grows downward from the top of the main display.
        let frame = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.height - dockHeight + 2, width: width, height: height)

        var items: [CGRect] = []
        var x = frame.minX + padding
        for group in groups {
            for _ in 0..<group {
                items.append(CGRect(x: x, y: frame.minY + (height - tileSize) / 2, width: tileSize, height: tileSize))
                x += tileSize
            }
            x += separatorWidth
        }
        return DockLayout(frame: frame, itemFrames: items, isExact: false)
    }

    private static func bundleIdentifiers(in tiles: [Any]?) -> [String] {
        (tiles ?? []).compactMap { tile in
            ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        }
    }
}
