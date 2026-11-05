import SwiftUI

/// A white SF Symbol on a rounded, gradient-filled square, like the icons in
/// System Settings.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The app's emblem: a snowflake on a frosty, round gradient.
struct SeasonBadge: View {
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: "snowflake")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.2, green: 0.25, blue: 0.75)], startPoint: .topLeading,
                    endPoint: .bottomTrailing),
                in: .circle
            )
            .shadow(color: .blue.opacity(0.35), radius: size * 0.15, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

/// A slider in a form row, with its current value shown on the right.
struct SliderRow<Value: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var minimumImage: String?
    var maximumImage: String?
    @ViewBuilder var valueLabel: (Double) -> Value

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range) {
                    Text(title)
                } minimumValueLabel: {
                    if let minimumImage { Image(systemName: minimumImage).foregroundStyle(.secondary) }
                } maximumValueLabel: {
                    if let maximumImage { Image(systemName: maximumImage).foregroundStyle(.secondary) }
                }
                .labelsHidden()

                valueLabel(value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(maxWidth: 300)
        } label: {
            Text(title)
        }
    }
}

extension SliderRow where Value == Text {
    /// A slider showing its value as a multiplier, like "1.5×".
    init(multiplier title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, minimumImage: String? = nil, maximumImage: String? = nil)
    {
        self.init(title: title, value: value, range: range, minimumImage: minimumImage, maximumImage: maximumImage) { value in
            Text(value, format: .number.precision(.fractionLength(1))) + Text("×")
        }
    }

    /// A slider showing its value as a percentage of its range.
    init(
        percent title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double> = 0...1, minimumImage: String? = nil,
        maximumImage: String? = nil
    ) {
        self.init(title: title, value: value, range: range, minimumImage: minimumImage, maximumImage: maximumImage) { value in
            Text((value - range.lowerBound) / (range.upperBound - range.lowerBound), format: .percent.precision(.fractionLength(0)))
        }
    }
}

/// A rounded "night sky" card that hosts a live preview.
struct PreviewCard<Content: View>: View {
    var caption: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.2), Color(red: 0.13, green: 0.16, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            content
            if let caption {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial.opacity(0.6), in: .capsule)
                    .padding(10)
            }
        }
        .frame(height: 180)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}

/// A row explaining that Accessibility access makes Dock effects exact.
struct AccessibilityStatusRow: View {
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(isGranted ? "Dock access is on" : "The Dock's size is estimated")
                    .font(.callout.weight(.medium))
                Text(
                    isGranted
                        ? "Snow and lights line up with the Dock exactly." : "Allow Accessibility access so snow and lights line up with the Dock exactly."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !isGranted {
                Button("Allow Access…", action: request)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
