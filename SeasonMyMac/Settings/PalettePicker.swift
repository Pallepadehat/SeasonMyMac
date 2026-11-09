import SeasonKit
import SwiftUI

extension LightPalette {
    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .warmWhite: "Warm White"
        case .icy: "Icy"
        case .candyCane: "Candy Cane"
        case .aurora: "Aurora"
        case .gold: "Gold"
        case .peppermint: "Peppermint"
        case .frosted: "Frosted"
        case .fireside: "Fireside"
        case .forest: "Forest"
        case .royal: "Royal"
        case .nordic: "Nordic"
        case .pastel: "Pastel"
        case .neon: "Neon"
        case .rainbow: "Rainbow"
        }
    }

    var swatchColors: [Color] {
        colors.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
    }
}

extension LightAnimation {
    var title: LocalizedStringKey {
        switch self {
        case .steady: "Steady"
        case .twinkle: "Twinkle"
        case .chase: "Chase"
        case .breathe: "Breathe"
        case .sparkle: "Sparkle"
        case .alternate: "Alternate"
        case .colorWave: "Color Wave"
        }
    }

    var systemImage: String {
        switch self {
        case .steady: "lightbulb.fill"
        case .twinkle: "sparkles"
        case .chase: "arrow.right.circle"
        case .breathe: "waveform.path"
        case .sparkle: "sparkle"
        case .alternate: "circle.lefthalf.filled"
        case .colorWave: "rainbow"
        }
    }
}

/// A circle split into a palette's colours, like the accent colour picker in System Settings.
struct PaletteDot: View {
    let palette: LightPalette
    var size: CGFloat = 20
    var isSelected = false

    var body: some View {
        Circle()
            .fill(AngularGradient(stops: stops, center: .center, angle: .degrees(-90)))
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .overlay {
                if isSelected {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.32, height: size * 0.32)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
            }
            .frame(width: size, height: size)
            .padding(3)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
    }

    /// Hard-edged slices, one per colour.
    private var stops: [Gradient.Stop] {
        let colors = palette.swatchColors
        let slice = 1 / Double(colors.count)
        return colors.enumerated().flatMap { index, color in
            [Gradient.Stop(color: color, location: Double(index) * slice), Gradient.Stop(color: color, location: Double(index + 1) * slice)]
        }
    }
}

/// A grid of palettes to pick from.
struct PalettePicker: View {
    @Binding var selection: LightPalette
    /// Shows each palette's name underneath (in Settings); otherwise names show on hover.
    var showsTitles = true

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: showsTitles ? 64 : 26), spacing: showsTitles ? 8 : 6, alignment: .top)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: showsTitles ? 12 : 6) {
            ForEach(LightPalette.allCases) { palette in
                let isSelected = palette == selection
                Button {
                    selection = palette
                } label: {
                    VStack(spacing: 4) {
                        PaletteDot(palette: palette, size: showsTitles ? 22 : 18, isSelected: isSelected)
                        if showsTitles {
                            Text(palette.title)
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text(palette.title))
                .accessibilityLabel(Text(palette.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, showsTitles ? 4 : 0)
    }
}
