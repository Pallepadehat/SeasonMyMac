import AppKit
import SwiftUI

/// A borderless, transparent panel that floats above everything and shows a
/// SwiftUI view at its natural size.
///
/// The view is measured once and the panel keeps that size. (Letting an
/// `NSHostingView` drive a borderless window's size can loop on layout, and
/// measuring with `fittingSize` before the view has a width truncates text.)
func makeFloatingPanel<Content: View>(_ content: Content, size fixedSize: CGSize? = nil, ignoresMouse: Bool = false) -> NSPanel {
    let root = content.fixedSize()
    let size = fixedSize ?? NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: 4000, height: 4000))

    let hosting = NSHostingView(rootView: root)
    hosting.sizingOptions = []
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.autoresizingMask = [.width, .height]

    let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = ignoresMouse
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.contentView = hosting
    return panel
}
