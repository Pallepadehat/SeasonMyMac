#if DEBUG
    import AppKit
    import SwiftUI

    /// A window showing the app's floating UI side by side, for checking the
    /// design. Debug builds only: launch with `-uiGallery YES`.
    enum UIGallery {
        private static var window: NSWindow?

        static func showIfRequested(model: AppModel) {
            guard UserDefaults.standard.bool(forKey: "uiGallery") else { return }
            let content = HStack(alignment: .top, spacing: 30) {
                MenuBarView(model: model)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
                VStack(spacing: 30) {
                    PlayHUDView(holdKeys: .controlOption) {}
                    GiftRevealView(fact: SeasonFacts.all[19], start: Date(), finish: {}, frozenTime: 4)
                        .frame(width: 440, height: 560)
                }
            }
            .padding(30)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.3, green: 0.32, blue: 0.48), Color(red: 0.55, green: 0.5, blue: 0.58)], startPoint: .top, endPoint: .bottom))

            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "UI Gallery"
            window.contentView = hosting
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            self.window = window

            if let folder = UserDefaults.standard.string(forKey: "uiGallerySettings") {
                snapshotSettings(model: model, into: folder)
            }
            if UserDefaults.standard.bool(forKey: "uiGalleryGift") {
                // The real thing, through the real code path.
                let frame = NSScreen.main?.visibleFrame ?? .zero
                GiftReveal.shared.show(at: NSPoint(x: frame.midX, y: frame.midY - 160), on: NSScreen.main)
                if let path = UserDefaults.standard.string(forKey: "uiGalleryGiftOut") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        let panel = NSApplication.shared.windows.first { $0 is NSPanel && $0.frame.width == 440 }
                        if let view = panel?.contentView { save(view, to: path) }
                    }
                }
            }

            // Also save a picture of it, for reviewing without a screen.
            if let path = UserDefaults.standard.string(forKey: "uiGalleryOut") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let view = window.contentView { save(view, to: path) }
                }
            }
        }

        private static var settingsWindows: [NSWindow] = []

        /// Saves a picture of every Settings pane into `folder`.
        private static func snapshotSettings(model: AppModel, into folder: String) {
            for pane in SettingsPane.allCases {
                let hosting = NSHostingView(rootView: SettingsView(model: model, pane: pane).frame(width: 760, height: 720))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = hosting
                window.orderFront(nil)
                settingsWindows.append(window)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    save(hosting, to: "\(folder)/\(pane.rawValue).png")
                    window.orderOut(nil)
                }
            }
        }

        private static func save(_ view: NSView, to path: String) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
#endif
