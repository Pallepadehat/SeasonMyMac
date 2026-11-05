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
        }
    }

    var systemImage: String {
        switch self {
        case .steady: "lightbulb.fill"
        case .twinkle: "sparkles"
        case .chase: "arrow.right.circle"
        case .breathe: "waveform.path"
        }
    }
}

/// Glowing dots in a palette's colours.
struct PaletteSwatch: View {
    let palette: LightPalette
    var dotSize: CGFloat = 10

    var body: some View {
        HStack(spacing: dotSize * 0.4) {
            ForEach(Array(repeatedColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.gradient)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: color.opacity(0.8), radius: dotSize * 0.35)
            }
        }
    }

    /// Always four dots, so every swatch has the same width.
    private var repeatedColors: [Color] {
        let colors = palette.swatchColors
        return (0..<4).map { colors[$0 % colors.count] }
    }
}

/// A grid of palette cards to pick from.
struct PalettePicker: View {
    @Binding var selection: LightPalette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(LightPalette.allCases) { palette in
                let isSelected = palette == selection
                Button {
                    selection = palette
                } label: {
                    VStack(spacing: 8) {
                        PaletteSwatch(palette: palette)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.08, green: 0.1, blue: 0.22), in: .rect(cornerRadius: 8, style: .continuous))
                        Text(palette.title)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(palette.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
