import AppKit
import SeasonKit
import SwiftUI

// MARK: - Snow Play

struct PlayPane: View {
    @Bindable var model: AppModel

    private var play: Binding<PlaySettings> { $model.settings.play }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .play, description: "Roll snowballs, throw them, and build snowmen on your desktop.", isOn: play.isEnabled)
            }

            Section {
                SnowmanPreview(look: model.settings.play)
                    .listRowInsets(EdgeInsets())
            } footer: {
                if !model.settings.snow.isEnabled {
                    Text("Turn on snow to play with it.")
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                Section {
                    Picker("Grab snow by holding", selection: play.holdKeys) {
                        Text("Control-Option (⌃⌥)").tag(PlayKeys.controlOption)
                        Text("Option-Command (⌥⌘)").tag(PlayKeys.optionCommand)
                        Text("Control-Command (⌃⌘)").tag(PlayKeys.controlCommand)
                        Text("Only in Snow Play").tag(PlayKeys.off)
                    }
                    LabeledContent("Snow Play") {
                        Button(model.isPlayModeOn ? "Stop Snow Play" : "Start Snow Play") {
                            model.setPlayMode(!model.isPlayModeOn)
                        }
                    }
                } header: {
                    Text("How to Play")
                } footer: {
                    Text(
                        "Hold the keys and drag a drift to make a snowball. Roll it to make it bigger, and flick to throw. Stack three to build a snowman. Snow Play in the menu bar lets you play without holding keys; press Esc to stop."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Throwing") {
                    SliderRow(multiplier: "Throw Strength", value: play.throwPower, in: 0.5...2, minimumImage: "tortoise", maximumImage: "hare")
                    Toggle("Snowballs splat when they hit hard", isOn: play.splats)
                }

                Section {
                    Picker("Hat", selection: play.hat) {
                        Text("Random").tag(SnowmanHat.random)
                        Text("Top Hat").tag(SnowmanHat.topHat)
                        Text("Santa Hat").tag(SnowmanHat.santaHat)
                        Text("Beanie").tag(SnowmanHat.beanie)
                        Text("No Hat").tag(SnowmanHat.none)
                    }
                    Picker("Scarf", selection: play.scarf) {
                        Text("Random").tag(ScarfColor.random)
                        Text("Red").tag(ScarfColor.red)
                        Text("Green").tag(ScarfColor.green)
                        Text("Blue").tag(ScarfColor.blue)
                        Text("Gold").tag(ScarfColor.gold)
                        Text("No Scarf").tag(ScarfColor.none)
                    }
                    Toggle("Carrot nose", isOn: play.hasCarrotNose)
                    Toggle("Stick arms", isOn: play.hasArms)
                    SliderRow(title: "Maximum Snowmen", value: play.maxSnowmen, range: 1...12, minimumImage: "person", maximumImage: "person.3.fill") { value in
                        Text("\(Int(value.rounded()))")
                    }
                } header: {
                    Text("Snowmen")
                } footer: {
                    Text(
                        "Drag a snowman to move it, or double-click it to melt it. Shift-drag takes off its head."
                    )
                    .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button("Build a Snowman", action: model.buildSnowman)
                        Spacer()
                        Button("Melt All Snowmen", role: .destructive, action: model.clearSnowmen)
                    }
                }
            }
            .disabled(!model.settings.play.isEnabled || !model.settings.snow.isEnabled)
        }
        .formStyle(.grouped)
    }
}

/// A drawing of a snowman dressed the way the settings say.
private struct SnowmanPreview: View {
    let look: PlaySettings
    @State private var style: UInt32 = 0

    var body: some View {
        PreviewCard {
            Canvas { context, size in
                let ground = size.height - 26
                context.fill(Path(CGRect(x: 0, y: ground, width: size.width, height: 26)), with: .color(.white.opacity(0.9)))
                drawSnowman(in: &context, base: CGPoint(x: size.width / 2, y: ground + 4))
            }
            .onTapGesture { style = UInt32.random(in: 0...UInt32.max) }
            .help(Text("Click for another outfit"))
        }
    }

    private func drawSnowman(in context: inout GraphicsContext, base: CGPoint) {
        let radii: [CGFloat] = [34, 25, 18]
        var centers: [CGPoint] = []
        var y = base.y
        for (index, radius) in radii.enumerated() {
            y -= index == 0 ? radius * 0.9 : radii[index - 1] * 0.78 + radius * 0.8
            centers.append(CGPoint(x: base.x, y: y))
        }
        let snow = Gradient(colors: [.white, Color(red: 0.75, green: 0.82, blue: 0.94)])
        let stick = Color(red: 0.33, green: 0.21, blue: 0.12)
        let coal = Color(white: 0.08)

        if look.hasArms {
            for side in [-1.0, 1.0] {
                var arm = Path()
                arm.move(to: CGPoint(x: centers[1].x + side * radii[1] * 0.6, y: centers[1].y - radii[1] * 0.15))
                arm.addLine(to: CGPoint(x: centers[1].x + side * radii[1] * 1.9, y: centers[1].y - radii[1] * 0.9))
                context.stroke(arm, with: .color(stick), lineWidth: 2.5)
            }
        }
        for (center, radius) in zip(centers, radii) {
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    snow, center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.5))
        }
        for index in -1...1 {
            let point = CGPoint(x: centers[1].x, y: centers[1].y + CGFloat(index) * radii[1] * 0.42)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(coal))
        }

        let head = centers[2], r = radii[2]
        if let scarf = scarfColor {
            let band = CGRect(x: head.x - r, y: centers[1].y - radii[1] * 0.72 - r * 0.2, width: r * 2, height: r * 0.4)
            context.fill(Path(roundedRect: band, cornerRadius: r * 0.15), with: .color(scarf))
            context.fill(
                Path(roundedRect: CGRect(x: head.x + r * 0.3, y: band.midY, width: r * 0.38, height: radii[1] * 0.75), cornerRadius: 3), with: .color(scarf))
        }
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: head.x + side * r * 0.32 + r * 0.06, y: head.y - r * 0.28)
            context.fill(Path(ellipseIn: CGRect(x: eye.x - 2.2, y: eye.y - 2.2, width: 4.4, height: 4.4)), with: .color(coal))
        }
        if look.hasCarrotNose {
            var nose = Path()
            nose.move(to: CGPoint(x: head.x + r * 0.05, y: head.y - r * 0.14))
            nose.addLine(to: CGPoint(x: head.x + r * 1.0, y: head.y + r * 0.08))
            nose.addLine(to: CGPoint(x: head.x + r * 0.05, y: head.y + r * 0.12))
            context.fill(nose, with: .color(.orange))
        }

        switch hat {
        case .topHat:
            context.fill(
                Path(roundedRect: CGRect(x: head.x - r * 1.02, y: head.y - r * 0.88, width: r * 2.04, height: r * 0.2), cornerRadius: 2), with: .color(coal))
            context.fill(
                Path(roundedRect: CGRect(x: head.x - r * 0.66, y: head.y - r * 1.9, width: r * 1.32, height: r * 1.08), cornerRadius: 2), with: .color(coal))
            context.fill(Path(CGRect(x: head.x - r * 0.66, y: head.y - r * 1.08, width: r * 1.32, height: r * 0.2)), with: .color(.red))
        case .santaHat:
            var cone = Path()
            cone.move(to: CGPoint(x: head.x - r * 0.9, y: head.y - r * 0.6))
            cone.addQuadCurve(to: CGPoint(x: head.x + r * 1.05, y: head.y - r * 1.95), control: CGPoint(x: head.x - r * 0.1, y: head.y - r * 2.3))
            cone.addLine(to: CGPoint(x: head.x + r * 0.9, y: head.y - r * 0.6))
            context.fill(cone, with: .color(Color(red: 0.85, green: 0.12, blue: 0.14)))
            context.fill(
                Path(roundedRect: CGRect(x: head.x - r, y: head.y - r * 0.85, width: r * 2, height: r * 0.4), cornerRadius: r * 0.2), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: head.x + r * 0.8, y: head.y - r * 2.2, width: r * 0.5, height: r * 0.5)), with: .color(.white))
        case .beanie:
            let wool = scarfColor ?? .red
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r * 1.25, width: r * 2, height: r * 1.6)).intersection(
                    Path(CGRect(x: head.x - r, y: head.y - r * 1.3, width: r * 2, height: r * 0.88))), with: .color(wool))
            context.fill(
                Path(roundedRect: CGRect(x: head.x - r * 1.02, y: head.y - r * 0.6, width: r * 2.04, height: r * 0.34), cornerRadius: 3),
                with: .color(wool.opacity(0.85)))
            context.fill(Path(ellipseIn: CGRect(x: head.x - r * 0.24, y: head.y - r * 1.55, width: r * 0.48, height: r * 0.48)), with: .color(.white))
        case .none, .random:
            break
        }
    }

    private var hat: SnowmanHat {
        guard look.hat == .random else { return look.hat }
        return [SnowmanHat.topHat, .santaHat, .beanie][Int(style % 3)]
    }

    private var scarfColor: Color? {
        let color = SnowmanLook(hat: look.hat, scarf: look.scarf).scarfColor(style: style)
        guard color.w > 0 else { return nil }
        return Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z))
    }
}

// MARK: - Winter Magic

struct ExtrasPane: View {
    @Bindable var model: AppModel

    private var extras: Binding<WinterExtras> { $model.settings.extras }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .extras, description: "Santa's sleigh, frost on the screen, and a little more Christmas.")
            }

            Section {
                Toggle("Santa's sleigh flies by", isOn: extras.sleigh)
                Picker("Frequency", selection: extras.sleighFrequency) {
                    Text("Rarely").tag(SleighFrequency.rarely)
                    Text("Sometimes").tag(SleighFrequency.sometimes)
                    Text("Often").tag(SleighFrequency.often)
                }
                .pickerStyle(.segmented)
                .disabled(!model.settings.extras.sleigh)
                Toggle("Santa drops presents", isOn: extras.sleighDropsGifts)
                    .disabled(!model.settings.extras.sleigh)
                LabeledContent("Presents") {
                    Button("Open a Present", action: model.openPresent)
                }
                LabeledContent("Sleigh") {
                    Button("Call Santa Now", action: model.callSanta)
                        .disabled(!model.settings.extras.sleigh)
                }
            } header: {
                Text("Santa")
            } footer: {
                Text(
                    "Santa crosses the sky now and then and may drop a present. In Snow Play, click a present to open it."
                )
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Frost in the corners of the screen", isOn: extras.frost)
                SliderRow(percent: "Amount", value: extras.frostAmount, in: 0.2...1, minimumImage: "circle.dotted", maximumImage: "circle.dashed.inset.filled")
                    .disabled(!model.settings.extras.frost)
            } header: {
                Text("Frost")
            } footer: {
                Text("Frost grows slowly from the corners of the screen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Snowstorm") {
                    Button("Let It Snow", action: model.letItSnow)
                        .disabled(!model.settings.snow.isEnabled)
                }
                Toggle("Days until Christmas in the menu bar", isOn: extras.countdownInMenuBar)
                if model.settings.extras.countdownInMenuBar {
                    Picker("Countdown", selection: extras.countdownStyle) {
                        Text("\(model.daysUntilChristmas) days until Christmas").tag(CountdownStyle.full)
                        Text("\(model.daysUntilChristmas) days").tag(CountdownStyle.short)
                    }
                }
            } header: {
                Text("More")
            } footer: {
                Text("Let It Snow turns the snowfall into a blizzard for 30 seconds.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lights and music

struct MusicSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.lights.dancesToMusic) {
                Text("Follow music")
            }
            if model.settings.lights.dancesToMusic {
                LabeledContent("Now playing") {
                    if let playing = model.music.nowPlaying {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                                .foregroundStyle(.orange)
                            Text(playing.title.isEmpty ? playing.player.rawValue : "\(playing.title) — \(playing.artist)")
                                .lineLimit(1)
                        }
                    } else {
                        Text("Nothing in Apple Music or Spotify")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Music")
        } footer: {
            Text(
                "While Apple Music or Spotify is playing, the lights flash with the beat. macOS asks for permission the first time. No audio is recorded."
            )
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Displays

struct DisplaysPane: View {
    @Bindable var model: AppModel
    @State private var displays = DisplayInfo.connected
    @State private var selectedID: String?

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .displays, description: "Choose what appears on each display.")
            }

            Section {
                Picker("Show on", selection: $model.settings.visibility.displays) {
                    Text("All Displays").tag(VisibilitySettings.DisplayMode.all)
                    Text("Main Display Only").tag(VisibilitySettings.DisplayMode.main)
                    Text("Choose for Each").tag(VisibilitySettings.DisplayMode.custom)
                }
                .pickerStyle(.segmented)

                DisplayArrangement(displays: displays, selectedID: selection, isShowing: isShowing) { selectedID = $0 }
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                HStack {
                    Text("Click a display to choose what it shows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Identify Displays", action: model.identifyDisplays)
                }
            } header: {
                Text("Displays")
            }

            if let display = displays.first(where: { $0.id == selection }) {
                Section {
                    effectToggle("Snow", systemImage: "snowflake", keyPath: \.snow, display: display)
                    effectToggle("Snow Play", systemImage: "hand.raised.fill", keyPath: \.snowPlay, display: display)
                    effectToggle("Lights on the Dock", systemImage: "dock.rectangle", keyPath: \.dockLights, display: display)
                    effectToggle("Lights along the top", systemImage: "menubar.rectangle", keyPath: \.topLights, display: display)
                    effectToggle("Frost", systemImage: "snowflake.circle", keyPath: \.frost, display: display)
                    effectToggle("Santa's sleigh", systemImage: "gift.fill", keyPath: \.sleigh, display: display)
                } header: {
                    HStack {
                        Text(display.name)
                        if display.isMain {
                            Text("Main")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                } footer: {
                    Text("An effect that's turned off in its own settings stays off on every display. Dock lights appear on the display with the Dock.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayInfo.connected
        }
    }

    private var selection: String? {
        selectedID.flatMap { id in displays.contains { $0.id == id } ? id : nil } ?? displays.first?.id
    }

    private func effects(for display: DisplayInfo) -> DisplayEffects {
        let visibility = model.settings.visibility
        switch visibility.displays {
        case .all: return DisplayEffects()
        case .main:
            return display.isMain
                ? DisplayEffects() : DisplayEffects(snow: false, snowPlay: false, dockLights: false, topLights: false, frost: false, sleigh: false)
        case .custom: return visibility.effects(for: display.id)
        }
    }

    private func isShowing(_ display: DisplayInfo) -> Bool {
        effects(for: display).showsAnything
    }

    private func effectToggle(_ title: LocalizedStringKey, systemImage: String, keyPath: WritableKeyPath<DisplayEffects, Bool>, display: DisplayInfo)
        -> some View
    {
        Toggle(
            isOn: Binding {
                effects(for: display)[keyPath: keyPath]
            } set: { isOn in
                var effects = effects(for: display)
                effects[keyPath: keyPath] = isOn
                model.setEffects(effects, for: display)
            }
        ) {
            Text(title)
        }
    }
}

/// The displays drawn the way they're arranged in System Settings.
private struct DisplayArrangement: View {
    let displays: [DisplayInfo]
    let selectedID: String?
    let isShowing: (DisplayInfo) -> Bool
    let select: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = bounds.isNull ? 1 : min((proxy.size.width - 20) / bounds.width, (proxy.size.height - 20) / bounds.height)
            let offset = CGPoint(
                x: (proxy.size.width - bounds.width * scale) / 2,
                y: (proxy.size.height - bounds.height * scale) / 2)

            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let frame = display.frame
                    // Cocoa's y grows upward; the drawing's grows downward.
                    let rect = CGRect(
                        x: offset.x + (frame.minX - bounds.minX) * scale,
                        y: offset.y + (bounds.maxY - frame.maxY) * scale,
                        width: frame.width * scale,
                        height: frame.height * scale
                    ).insetBy(dx: 3, dy: 3)
                    DisplayTile(display: display, isSelected: display.id == selectedID, isShowing: isShowing(display))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { select(display.id) }
                }
            }
        }
    }
}

/// A display drawn like the ones in System Settings' arrangement view.
private struct DisplayTile: View {
    let display: DisplayInfo
    let isSelected: Bool
    let isShowing: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isShowing ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25))
            if display.isMain {
                // The menu bar.
                UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.85))
                    .frame(height: 5)
            }
            Text(display.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isShowing ? .white : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(6)
                .frame(maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isSelected ? Color.primary.opacity(0.85) : .clear, lineWidth: 2.5)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Updates

struct UpdatesSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Section {
            LabeledContent("Version \(updater.currentVersion)") {
                if let version = updater.availableVersion {
                    Button("Install \(version)…", action: updater.checkNow)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                } else {
                    Button("Check for Updates…", action: updater.checkNow)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            Toggle(isOn: $updater.checksAutomatically) {
                Text("Check for new versions automatically")
                Text("Once a day it downloads a small file from GitHub listing the latest release. Nothing about you is sent.")
            }
            Toggle(isOn: $updater.downloadsAutomatically) {
                Text("Download and install updates automatically")
                Text("New versions install quietly the next time SeasonMyMac starts.")
            }
            .disabled(!updater.checksAutomatically)
        } header: {
            Text("Updates")
        } footer: {
            if let lastCheck = updater.lastCheck {
                Text("Last checked \(lastCheck, format: .relative(presentation: .named)).")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
