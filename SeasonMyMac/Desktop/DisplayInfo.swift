import AppKit

/// A connected display, identified in a way that survives restarts and
/// reconnecting, so per-display choices stick to the right screen.
struct DisplayInfo: Identifiable, Equatable {
    /// The display's UUID from Core Graphics, or its name when that's unavailable.
    let id: String
    let name: String
    /// The display with the menu bar.
    let isMain: Bool
    /// The frame in Cocoa coordinates, for drawing the arrangement.
    let frame: CGRect

    init(screen: NSScreen) {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(), let string = CFUUIDCreateString(nil, uuid) as String? {
            id = string
        } else {
            id = screen.localizedName
        }
        name = screen.localizedName
        isMain = screen == NSScreen.screens.first
        frame = screen.frame
    }

    static var connected: [DisplayInfo] {
        NSScreen.screens.map(DisplayInfo.init)
    }
}
