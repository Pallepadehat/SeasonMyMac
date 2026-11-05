import AppKit
import SeasonKit
import SwiftUI

/// The panel that opens from the menu bar icon: quick toggles in the style of
/// Control Center, plus the settings people reach for most.
struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                FeatureTile(title: "Snow", systemImage: "snowflake", tint: .blue, isOn: $model.settings.snow.isEnabled)
                FeatureTile(title: "Lights", systemImage: "lightbulb.max.fill", tint: .orange, isOn: $model.settings.lights.isEnabled)
            }

            if model.settings.snow.isEnabled {
                snowCard
            }
            if model.settings.lights.isEnabled {
                lightsCard
            }
            if model.settings.needsDock, !model.isAccessibilityGranted {
                accessibilityBanner
            }

            HStack(spacing: 8) {
                Button(action: model.shakeOffAllSnow) {
                    Label("Shake Off Snow", systemImage: "wind")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.settings.snow.isEnabled)

                Button(action: showSettings) {
                    Label("Settings…", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)

            Divider()

            HStack {
                Text("SeasonMyMac")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
        .animation(.snappy(duration: 0.25), value: model.settings.snow.isEnabled)
        .animation(.snappy(duration: 0.25), value: model.settings.lights.isEnabled)
        .task {
            while !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            SeasonBadge(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.settings.season.title)
                    .font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
    }

    private var snowCard: some View {
        Card {
            HStack {
                Text("Intensity")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(intensityName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $model.settings.snow.intensity, in: 0.05...1) {
                Text("Intensity")
            } minimumValueLabel: {
                Image(systemName: "cloud.snow")
            } maximumValueLabel: {
                Image(systemName: "wind.snow")
            }
            .labelsHidden()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var lightsCard: some View {
        Card {
            HStack(spacing: 6) {
                PlacementChip(title: "Dock", systemImage: "dock.rectangle", isOn: $model.settings.lights.onDock)
                PlacementChip(title: "Top of Screen", systemImage: "menubar.rectangle", isOn: $model.settings.lights.alongTop)
            }
            HStack {
                Text("Colors")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Animation", selection: $model.settings.lights.effect) {
                    ForEach(LightAnimation.allCases) { animation in
                        Label(animation.title, systemImage: animation.systemImage).tag(animation)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            HStack(spacing: 6) {
                ForEach(LightPalette.allCases) { palette in
                    let isSelected = model.settings.lights.palette == palette
                    Button {
                        model.settings.lights.palette = palette
                    } label: {
                        PaletteSwatch(palette: palette, dotSize: 5)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.08, green: 0.1, blue: 0.22), in: .rect(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(Text(palette.title))
                    .accessibilityLabel(Text(palette.title))
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var accessibilityBanner: some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "dock.rectangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Accessibility access so snow and lights fit the Dock exactly.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Allow Access…", action: model.requestAccessibility)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Helpers

    private var status: LocalizedStringKey {
        switch (model.settings.snow.isEnabled, model.settings.lights.isEnabled) {
        case (true, true): "\(intensityName) and twinkling lights"
        case (true, false): "\(intensityName)"
        case (false, true): "Lights are on"
        case (false, false): "Taking a break"
        }
    }

    private var intensityName: String {
        switch model.settings.snow.intensity {
        case ..<0.25: String(localized: "Light flurries")
        case ..<0.55: String(localized: "Gentle snowfall")
        case ..<0.8: String(localized: "Heavy snow")
        default: String(localized: "Blizzard")
        }
    }

    private func showSettings() {
        // A menu bar app isn't active by default, so bring the window forward.
        NSApplication.shared.activate()
        openSettings()
    }
}

/// A big, tappable on/off tile, like the ones in Control Center.
private struct FeatureTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .background(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                    .symbolEffect(.bounce, value: isOn)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(isOn ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// A small on/off pill for choosing where the lights hang.
private struct PlacementChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.white : .primary)
                .background(isOn ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(.quaternary), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// A softly filled group within the panel.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
    }
}
