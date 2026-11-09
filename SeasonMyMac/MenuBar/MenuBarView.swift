import AppKit
import SeasonKit
import SwiftUI

/// The panel that opens from the menu bar icon, laid out like the system's
/// own menu bar panels: toggles and sliders on top, then menu-style actions.
struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 0) {
                ModuleToggle(title: "Snow", systemImage: "snowflake", isOn: $model.settings.snow.isEnabled)
                ModuleToggle(title: "Lights", systemImage: "lightbulb.fill", isOn: $model.settings.lights.isEnabled)
                ModuleToggle(title: "Snow Play", systemImage: "hand.raised.fill", isOn: playBinding)
                    .disabled(!canPlay)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            if model.settings.snow.isEnabled {
                section("Snowfall") {
                    LabeledSlider(value: $model.settings.snow.intensity, in: 0.05...1, minimumImage: "cloud.snow", maximumImage: "cloud.snow.fill")
                }
            }

            if model.settings.lights.isEnabled {
                section("Lights") {
                    VStack(spacing: 8) {
                        PalettePicker(selection: $model.settings.lights.palette, showsTitles: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text("Effect")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("Effect", selection: $model.settings.lights.effect) {
                                ForEach(LightAnimation.allCases) { animation in
                                    Text(animation.title).tag(animation)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .controlSize(.small)
                        }
                        CompactToggle(title: "On the Dock", isOn: $model.settings.lights.onDock)
                        CompactToggle(title: "Along the top", isOn: $model.settings.lights.alongTop)
                        CompactToggle(title: "Follow music", isOn: $model.settings.lights.dancesToMusic)
                    }
                }
                if model.settings.lights.dancesToMusic, let playing = model.music.nowPlaying {
                    NowPlayingRow(playing: playing, isFollowingBeat: model.music.isFollowingBeat)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }

            MenuDivider()

            if let version = model.updater.availableVersion {
                MenuRow(title: "Update to Version \(version)…", systemImage: "arrow.down.circle.fill", isProminent: true, action: model.updater.checkNow)
                MenuDivider()
            }
            if model.settings.needsDock, !model.isAccessibilityGranted {
                MenuRow(title: "Allow Dock Access…", systemImage: "exclamationmark.triangle.fill", action: model.requestAccessibility)
                MenuDivider()
            }

            Group {
                MenuRow(title: "Build a Snowman", systemImage: "figure.stand", action: model.buildSnowman)
                    .disabled(!model.settings.snow.isEnabled)
                MenuRow(title: "Let It Snow", systemImage: "cloud.snow", action: model.letItSnow)
                    .disabled(!model.settings.snow.isEnabled)
                MenuRow(title: "Call Santa", systemImage: "bell", action: model.callSanta)
                    .disabled(!model.settings.extras.sleigh)
                MenuRow(title: "Open a Present", systemImage: "gift", action: model.openPresent)
            }
            MenuDivider()
            Group {
                MenuRow(title: "Shake Off Snow", systemImage: "wind", action: model.shakeOffAllSnow)
                    .disabled(!model.settings.snow.isEnabled)
                MenuRow(title: "Melt Snowmen", systemImage: "drop", action: model.clearSnowmen)
                    .disabled(!model.settings.snow.isEnabled)
            }
            MenuDivider()
            MenuRow(title: "Settings…", shortcut: "⌘,", action: showSettings)
                .keyboardShortcut(",")
            MenuRow(title: "Quit SeasonMyMac", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.bottom, 6)
        .frame(width: 300)
        .animation(.smooth(duration: 0.25), value: model.settings.snow.isEnabled)
        .animation(.smooth(duration: 0.25), value: model.settings.lights.isEnabled)
        .animation(.smooth(duration: 0.25), value: model.music.nowPlaying)
        .task {
            while !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("SeasonMyMac")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    // MARK: Helpers

    private var canPlay: Bool {
        model.settings.snow.isEnabled && model.settings.play.isEnabled
    }

    private var playBinding: Binding<Bool> {
        Binding {
            model.isPlayModeOn
        } set: {
            model.setPlayMode($0)
        }
    }

    private var subtitle: String {
        let days = model.daysUntilChristmas
        switch days {
        case 0: return String(localized: "Merry Christmas")
        case 1: return String(localized: "Christmas is tomorrow")
        default: return String(localized: "\(days) days until Christmas")
        }
    }

    private func showSettings() {
        // A menu bar app isn't active by default, so bring the window forward.
        NSApplication.shared.activate()
        openSettings()
    }
}

// MARK: - Controls

/// A round toggle with its name underneath, like the modules in Control Center.
private struct ModuleToggle: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// A slider with symbols at both ends, like the ones in Control Center.
private struct LabeledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let minimumImage: String
    let maximumImage: String

    init(value: Binding<Double>, in range: ClosedRange<Double>, minimumImage: String, maximumImage: String) {
        _value = value
        self.range = range
        self.minimumImage = minimumImage
        self.maximumImage = maximumImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: minimumImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: $value, in: range)
                .controlSize(.small)
            Image(systemName: maximumImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }
}

/// A label with a small switch on the right.
private struct CompactToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle(isOn: $isOn) {
                Text(title)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}

/// The track playing in Apple Music or Spotify.
private struct NowPlayingRow: View {
    let playing: MusicSync.NowPlaying
    let isFollowingBeat: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: .rect(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(playing.title.isEmpty ? playing.player.rawValue : playing.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(playing.artist.isEmpty ? playing.player.rawValue : playing.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isFollowingBeat)
                .help(Text(isFollowingBeat ? "The lights follow the beat" : "The lights pulse along"))
        }
    }
}

/// A row that behaves like a menu item: highlighted under the pointer.
private struct MenuRow: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var shortcut: String?
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(isHighlighted ? Color.white : isProminent ? Color.accentColor : Color.secondary)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(isHighlighted ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor : .clear)
            }
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }

    private var isHighlighted: Bool {
        isHovered && isEnabled
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }
}
