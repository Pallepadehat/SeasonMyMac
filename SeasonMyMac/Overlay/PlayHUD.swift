import AppKit
import SwiftUI

/// A small floating card at the top of the screen while Snow Play is on:
/// how to play, and a button to stop.
final class PlayHUD {
    var onDone: (() -> Void)?

    private var panel: NSPanel?

    func show(on screen: NSScreen?, holdKeys: PlayKeys) {
        hide()
        guard let screen else { return }

        let panel = makeFloatingPanel(PlayHUDView(holdKeys: holdKeys) { [weak self] in self?.onDone?() })
        let size = panel.frame.size

        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

/// A compact pill, like the system's own on-screen indicators.
struct PlayHUDView: View {
    let holdKeys: PlayKeys
    let done: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Snow Play")
                    .font(.system(size: 13, weight: .semibold))
                Text("Drag snow to make a snowball.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Divider()
                .frame(height: 26)
            KeyCap("esc")
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .padding(20)
    }
}

/// A key drawn the way macOS shows keyboard shortcuts in help.
private struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
    }
}
