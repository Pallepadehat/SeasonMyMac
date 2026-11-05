import SeasonKit
import SwiftUI

extension Season {
    var title: LocalizedStringKey {
        switch self {
        case .christmas: "Christmas"
        case .halloween: "Halloween"
        case .newYear: "New Year"
        }
    }

    var tagline: LocalizedStringKey {
        switch self {
        case .christmas: "Falling snow and twinkling lights"
        case .halloween: "Bats, fog and flickering pumpkins"
        case .newYear: "Fireworks and confetti at midnight"
        }
    }

    var tint: Color {
        switch self {
        case .christmas: .blue
        case .halloween: .orange
        case .newYear: .purple
        }
    }
}

/// A selectable card for a season. Seasons that aren't ready yet show as
/// "Coming Soon".
struct SeasonCard: View {
    let season: Season
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsIcon(systemName: season.symbolName, color: season.tint, size: 30)
                    Spacer()
                    if !season.isAvailable {
                        Text("Coming Soon")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(season.title)
                        .font(.callout.weight(.semibold))
                    Text(season.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect)
            .opacity(season.isAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!season.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
