import AppKit
import SeasonKit
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: a sidebar of panes, like System Settings.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: SettingsPane

    init(model: AppModel, pane: SettingsPane = .snow) {
        self.model = model
        _selection = State(initialValue: pane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(systemName: pane.systemImage, color: pane.color)
                }
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 740, idealWidth: 760, minHeight: 560, idealHeight: 640)
        .task {
            // Accessibility can be granted at any time in System Settings.
            while !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralPane(model: model)
        case .snow: SnowPane(model: model)
        case .play: PlayPane(model: model)
        case .lights: LightsPane(model: model)
        case .extras: ExtrasPane(model: model)
        case .displays: DisplaysPane(model: model)
        case .apps: AppsPane(model: model)
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, snow, play, lights, extras, displays, apps

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .snow: "Snow"
        case .play: "Snow Play"
        case .lights: "Lights"
        case .extras: "Winter Magic"
        case .displays: "Displays"
        case .apps: "Apps"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .snow: "snowflake"
        case .play: "figure.stand"
        case .lights: "lightbulb.max.fill"
        case .extras: "sparkles"
        case .displays: "display.2"
        case .apps: "macwindow.on.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .snow: .blue
        case .play: .cyan
        case .lights: .orange
        case .extras: .red
        case .displays: .indigo
        case .apps: .purple
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var model: AppModel
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SeasonBadge(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SeasonMyMac")
                            .font(.title2.weight(.semibold))
                        Text("Seasonal magic for your desktop.")
                            .foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.shortVersion)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(Season.allCases) { season in
                        SeasonCard(season: season, isSelected: model.settings.season == season) {
                            model.settings.season = season
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Season")
            } footer: {
                Text("More seasons are on the way. Want to help build one? SeasonMyMac is open source.")
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: $model.launchesAtLogin)
                Toggle("Show days until Christmas in the menu bar", isOn: $model.settings.extras.countdownInMenuBar)
                if model.settings.extras.countdownInMenuBar {
                    Picker("Countdown", selection: $model.settings.extras.countdownStyle) {
                        Text("\(model.daysUntilChristmas) days until Christmas").tag(CountdownStyle.full)
                        Text("\(model.daysUntilChristmas) days").tag(CountdownStyle.short)
                    }
                }
            }

            UpdatesSection(updater: model.updater)

            Section {
                Picker("Frame Rate", selection: $model.settings.performance) {
                    Text("Battery Saver").tag(PerformanceMode.batterySaver)
                    Text("Balanced").tag(PerformanceMode.balanced)
                    Text("Smooth").tag(PerformanceMode.smooth)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Performance")
            } footer: {
                Text(model.settings.performance.explanation)
                    .foregroundStyle(.secondary)
            }

            Section("Dock") {
                AccessibilityStatusRow(isGranted: model.isAccessibilityGranted, request: model.requestAccessibility)
            }

            Section {
                HStack {
                    Button("Shake Off All Snow", action: model.shakeOffAllSnow)
                    Spacer()
                    Button("Restore Defaults…", role: .destructive) {
                        isConfirmingReset = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore all settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive, action: model.resetToDefaults)
        } message: {
            Text("Your app exceptions will be removed too.")
        }
    }
}

private extension PerformanceMode {
    var explanation: LocalizedStringKey {
        switch self {
        case .batterySaver: "Always 30 frames per second. Uses the least energy."
        case .balanced: "30 frames per second for drifting snow, 60 while snow tumbles or bulbs swing. Recommended."
        case .smooth: "Always 60 frames per second. Silky, but uses about twice the energy."
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Snow

private struct SnowPane: View {
    @Bindable var model: AppModel

    private var snow: Binding<SnowSettings> { $model.settings.snow }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .snow, description: "Snow falls across your desktop and settles on windows and the Dock.", isOn: snow.isEnabled)
            }

            Section {
                SnowPreview(settings: model.settings.snow)
                    .listRowInsets(EdgeInsets())
            }

            Group {
                Section("Snowfall") {
                    SliderRow(title: "Intensity", value: snow.intensity, range: 0.05...1, minimumImage: "cloud.snow", maximumImage: "wind.snow") { value in
                        Text(Self.intensityName(value))
                    }
                    SliderRow(multiplier: "Flake Size", value: snow.flakeSize, in: 0.5...2, minimumImage: "circle.fill", maximumImage: "snowflake")
                    SliderRow(multiplier: "Fall Speed", value: snow.fallSpeed, in: 0.4...2.5, minimumImage: "tortoise", maximumImage: "hare")
                }

                Section("Wind") {
                    SliderRow(percent: "Strength", value: snow.windStrength, minimumImage: "leaf", maximumImage: "wind")
                    SliderRow(title: "Direction", value: snow.windDirection, range: -1...1, minimumImage: "arrow.left", maximumImage: "arrow.right") { value in
                        Text(Self.directionName(value))
                    }
                }

                Section {
                    Toggle("Windows", isOn: snow.settlesOnWindows)
                    Toggle("Dock", isOn: snow.settlesOnDock)
                    if model.settings.snow.settlesOnDock, !model.isAccessibilityGranted {
                        AccessibilityStatusRow(isGranted: false, request: model.requestAccessibility)
                    }
                    SliderRow(title: "Snow Depth", value: snow.depth, range: 3...20, minimumImage: "minus", maximumImage: "plus") { value in
                        Text("\(Int(value.rounded())) pt")
                    }
                    SliderRow(multiplier: "Build-up Speed", value: snow.accumulation, in: 0.25...4, minimumImage: "hourglass", maximumImage: "bolt")
                    SliderRow(title: "Stickiness", value: snow.stickiness, range: 0...1, minimumImage: "drop", maximumImage: "hand.raised") { value in
                        Text(value < 0.33 ? "Slippery" : value < 0.66 ? "Packed" : "Sticky")
                    }
                } header: {
                    Text("Snow Settles On")
                } footer: {
                    Text(
                        "Snow rides along when you move a window gently, and flies off when you shake it, stop suddenly, or resize it. Stickier snow holds on longer."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Interaction") {
                    Toggle("Brush snow away with the pointer", isOn: snow.cursorBrushesSnow)
                    Button("Shake Off All Snow", action: model.shakeOffAllSnow)
                }
            }
            .disabled(!model.settings.snow.isEnabled)
        }
        .formStyle(.grouped)
    }

    private static func intensityName(_ value: Double) -> LocalizedStringKey {
        switch value {
        case ..<0.25: "Flurry"
        case ..<0.55: "Snowfall"
        case ..<0.8: "Heavy"
        default: "Blizzard"
        }
    }

    private static func directionName(_ value: Double) -> LocalizedStringKey {
        switch value {
        case ..<(-0.15): "Left"
        case ...0.15: "Calm"
        default: "Right"
        }
    }
}

// MARK: - Lights

private struct LightsPane: View {
    @Bindable var model: AppModel

    private var lights: Binding<LightSettings> { $model.settings.lights }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .lights, description: "Strings of holiday lights along the Dock and the top of the screen.", isOn: lights.isEnabled)
            }

            Section {
                LightsPreview(settings: model.settings.lights)
                    .listRowInsets(EdgeInsets())
            }

            Group {
                Section {
                    Toggle("On the Dock", isOn: lights.onDock)
                    if model.settings.lights.onDock {
                        Picker("Dock Style", selection: lights.dockStyle) {
                            Text("Along the Rim").tag(DockLightStyle.rim)
                            Text("Draped Between Icons").tag(DockLightStyle.draped)
                        }
                        .pickerStyle(.segmented)
                    }
                    if model.settings.lights.onDock, !model.isAccessibilityGranted {
                        AccessibilityStatusRow(isGranted: false, request: model.requestAccessibility)
                    }
                    Toggle("Along the top of the screen", isOn: lights.alongTop)
                } header: {
                    Text("Where")
                } footer: {
                    Text("Lights never block clicks. Everything underneath works as usual.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    SliderRow(
                        title: "Loop Width", value: lights.topLoopWidth, range: 40...160, minimumImage: "arrow.right.and.line.vertical.and.arrow.left",
                        maximumImage: "arrow.left.and.line.vertical.and.arrow.right"
                    ) { value in
                        Text("\(Int(value.rounded())) pt")
                    }
                    SliderRow(title: "Droop", value: lights.topDroop, range: 2...24, minimumImage: "minus", maximumImage: "chevron.down") { value in
                        Text("\(Int(value.rounded())) pt")
                    }
                    Picker("Show on", selection: lights.topOnAllDisplays) {
                        Text("All Displays").tag(true)
                        Text("Main Display Only").tag(false)
                    }
                } header: {
                    Text("Top of Screen")
                } footer: {
                    Text("The wire hangs from the bottom edge of the menu bar.")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.settings.lights.alongTop)

                Section("Colors") {
                    PalettePicker(selection: lights.palette)
                }

                MusicSection(model: model)

                Section("Style") {
                    Picker("Animation", selection: lights.effect) {
                        ForEach(LightAnimation.allCases) { animation in
                            Label(animation.title, systemImage: animation.systemImage).tag(animation)
                        }
                    }
                    SliderRow(percent: "Brightness", value: lights.brightness, in: 0.2...1, minimumImage: "sun.min", maximumImage: "sun.max.fill")
                    SliderRow(
                        multiplier: "Bulb Size", value: lights.bulbSize, in: 0.6...1.6, minimumImage: "smallcircle.filled.circle",
                        maximumImage: "circle.circle.fill")
                    SliderRow(multiplier: "Bulb Density", value: lights.density, in: 0.5...2, minimumImage: "ellipsis", maximumImage: "circle.grid.3x3.fill")
                    Toggle("Swing in the wind and when touched", isOn: lights.swings)
                }
            }
            .disabled(!model.settings.lights.isEnabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apps & Displays

private struct AppsPane: View {
    @Bindable var model: AppModel
    @State private var isImportingApp = false

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .apps, description: "Pause the effects for certain apps, or keep snow off their windows.")
            }

            Section {
                Toggle("Hide when an app is full screen", isOn: $model.settings.visibility.hidesInFullScreen)
            } header: {
                Text("Visibility")
            } footer: {
                Text("Effects fade out gracefully and pause completely, using no energy, while they're hidden.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.settings.visibility.appRules.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "app.dashed")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("No app exceptions")
                                .font(.callout.weight(.medium))
                            Text("Add apps where the seasons should take a break, like games or video editors.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 14)
                        Spacer()
                    }
                } else {
                    ForEach($model.settings.visibility.appRules) { $rule in
                        AppRuleRow(rule: $rule) {
                            model.removeRules([rule.id])
                        }
                    }
                }

                HStack {
                    Spacer()
                    addAppMenu
                }
            } header: {
                Text("App Exceptions")
            } footer: {
                Text(
                    "**Pause effects** hides snow and lights while the app is in front. **No snow on windows** keeps the effects, but snow won't settle on that app's windows."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImportingApp, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result {
                model.addRule(forAppAt: url)
            }
        }
    }

    private var addAppMenu: some View {
        Menu {
            Section("Running Apps") {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button {
                        if let identifier = app.bundleIdentifier {
                            model.addRule(AppRule(bundleIdentifier: identifier, name: app.localizedName ?? identifier))
                        }
                    } label: {
                        if let icon = app.icon {
                            Label {
                                Text(app.localizedName ?? "")
                            } icon: {
                                Image(nsImage: icon)
                            }
                        } else {
                            Text(app.localizedName ?? "")
                        }
                    }
                }
            }
            Divider()
            Button("Choose from Applications…") {
                isImportingApp = true
            }
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .fixedSize()
    }

    private var runningApps: [NSRunningApplication] {
        let excluded = Set(model.settings.visibility.appRules.map(\.bundleIdentifier) + [Bundle.main.bundleIdentifier ?? ""])
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !excluded.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

private struct AppRuleRow: View {
    @Binding var rule: AppRule
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
            Text(rule.name)
            Spacer()
            Picker("Behavior", selection: $rule.behavior) {
                Text("Pause effects").tag(AppRule.Behavior.pauseEffects)
                Text("No snow on windows").tag(AppRule.Behavior.noSnowOnWindows)
            }
            .labelsHidden()
            .fixedSize()
            Button("Remove", systemImage: "minus.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
