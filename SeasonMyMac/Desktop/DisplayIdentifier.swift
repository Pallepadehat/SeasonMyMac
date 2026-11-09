import AppKit
import SwiftUI

/// Briefly shows each display's name in big letters, so you can tell which
/// is which when choosing what each one shows.
enum DisplayIdentifier {
    private static var panels: [NSPanel] = []

    static func show() {
        hideAll()
        panels = NSScreen.screens.map { screen in
            let panel = makeFloatingPanel(Badge(display: DisplayInfo(screen: screen)), ignoresMouse: true)
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
            return panel
        }
        let shown = panels
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard panels.first === shown.first else { return }
            hideAll()
        }
    }

    private static func hideAll() {
        let old = panels
        panels = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            for panel in old { panel.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                for panel in old { panel.orderOut(nil) }
            }
        }
    }

    /// The display's name on a dark HUD, like the system's own on-screen indicators.
    private struct Badge: View {
        let display: DisplayInfo

        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: display.isMain ? "menubar.dock.rectangle" : "display")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(display.name)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                Text(display.isMain ? "Main Display" : "\(Int(display.frame.width)) × \(Int(display.frame.height))")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
            .background(.ultraThickMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .environment(\.colorScheme, .dark)
            .padding(30)
        }
    }
}
