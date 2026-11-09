import AppKit
import SwiftUI

/// Opens a present on the desktop: the box pops up and wiggles, the lid
/// flies off in a burst of confetti and light, and a gift tag rises out of
/// it with a fact about the season.
final class GiftReveal {
    static let shared = GiftReveal()

    private static let size = CGSize(width: 440, height: 560)
    /// Where the box sits in the panel, from its bottom-left corner.
    private static let boxBottom: CGFloat = 70

    private var panel: NSPanel?

    /// - Parameter point: Where the present was, in screen coordinates.
    func show(at point: NSPoint, on screen: NSScreen?) {
        close(animated: false)

        let view = GiftRevealView(fact: SeasonFacts.next(), start: Date()) { [weak self] in
            self?.close(animated: false)
        }
        // The animation fills a fixed stage; it has no natural size of its own.
        let panel = makeFloatingPanel(view.frame(width: Self.size.width, height: Self.size.height), size: Self.size)

        var origin = CGPoint(x: point.x - Self.size.width / 2, y: point.y - Self.boxBottom)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - Self.size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - Self.size.height)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func close(animated: Bool) {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - The animation

struct GiftRevealView: View {
    @State var fact: SeasonFacts.Fact
    let start: Date
    let finish: () -> Void
    /// Shows one moment of the animation instead of playing it (for previews and tools).
    var frozenTime: Double?

    @State private var closingSince: Date?
    @State private var isSettled = false
    @State private var isHovering = false
    @State private var confetti = Confetto.burst(count: 110)
    @State private var playedPop = false

    /// Timings, in seconds from the start.
    private let wiggleStart = 0.38
    private let burstTime = 1.15
    private let cardTime = 1.22

    var body: some View {
        TimelineView(.animation(paused: isSettled && closingSince == nil)) { timeline in
            let t = frozenTime ?? timeline.date.timeIntervalSince(start)
            let closing = closingSince.map { min(1, timeline.date.timeIntervalSince($0) / 0.42) } ?? 0

            GeometryReader { proxy in
                let size = proxy.size
                let boxCenter = CGPoint(x: size.width / 2, y: size.height - 70 - 30)

                ZStack {
                    rays(t: t, closing: closing)
                        .position(x: size.width / 2, y: 230)

                    flash(t: t)
                        .position(x: boxCenter.x, y: boxCenter.y - 34)

                    box(t: t)
                        .position(boxCenter)

                    lid(t: t)
                        .position(x: boxCenter.x, y: boxCenter.y - 34)

                    confettiLayer(t: t, origin: CGPoint(x: boxCenter.x, y: boxCenter.y - 36))

                    card(t: t, closing: closing, from: boxCenter)
                }
            }
            .onChange(of: t >= burstTime) { _, didBurst in
                if didBurst, !playedPop {
                    playedPop = true
                    NSSound(named: "Pop")?.play()
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.2))
            isSettled = true
            // Stays a while; longer while the pointer rests on it.
            var remaining = 14.0
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(0.5))
                if !isHovering { remaining -= 0.5 }
            }
            dismiss()
        }
    }

    private func dismiss() {
        guard closingSince == nil else { return }
        closingSince = Date()
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            finish()
        }
    }

    // MARK: Pieces

    /// A soft glow behind the card as it appears, fading once it settles.
    private func rays(t: Double, closing: Double) -> some View {
        let appear = smoothstep(burstTime, burstTime + 0.4, t) * (1 - smoothstep(burstTime + 1.2, burstTime + 2.4, t)) * (1 - closing)
        return Circle()
            .fill(RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.78).opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 200))
            .frame(width: 400, height: 400)
            .scaleEffect(0.6 + 0.4 * appear)
            .opacity(appear)
            .allowsHitTesting(false)
    }

    /// A bright pop of light the moment the lid comes off.
    private func flash(t: Double) -> some View {
        let since = t - burstTime
        let strength = since < 0 ? 0 : exp(-since * 7)
        return Circle()
            .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.85, blue: 0.5).opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 90))
            .frame(width: 180, height: 180)
            .scaleEffect(0.5 + (1 - strength) * 0.9)
            .opacity(strength)
            .allowsHitTesting(false)
    }

    private func box(t: Double) -> some View {
        let pop = easeOutBack(clamp01(t / wiggleStart))
        let wiggleTime = t - wiggleStart
        let envelope = clamp01(wiggleTime / (burstTime - wiggleStart))
        let isWiggling = wiggleTime > 0 && t < burstTime
        let angle = isWiggling ? sin(wiggleTime * 32) * (3 + 9 * envelope) : 0
        let squash = isWiggling ? 1 - 0.07 * envelope * (0.5 + 0.5 * sin(wiggleTime * 64)) : 1
        let fade = 1 - smoothstep(burstTime + 0.45, burstTime + 0.95, t)

        return GiftBox()
            .frame(width: 78, height: 60)
            .scaleEffect(x: pop * (2 - squash), y: pop * squash, anchor: .bottom)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .scaleEffect(0.9 + 0.1 * fade)
            .opacity(fade)
            .allowsHitTesting(false)
    }

    private func lid(t: Double) -> some View {
        let pop = easeOutBack(clamp01(t / wiggleStart))
        let since = max(0, t - burstTime)
        let wiggleTime = t - wiggleStart
        let rattle = wiggleTime > 0 && t < burstTime ? sin(wiggleTime * 47) * 2.5 * clamp01(wiggleTime / 0.6) : 0
        return GiftLid()
            .frame(width: 90, height: 34)
            .scaleEffect(pop)
            .rotationEffect(.degrees(since * 620 + rattle))
            .offset(x: since * 150, y: -since * 820 + since * since * 1250 - abs(rattle))
            .opacity(1 - smoothstep(0.55, 1.0, since))
            .allowsHitTesting(false)
    }

    private func confettiLayer(t: Double, origin: CGPoint) -> some View {
        let since = t - burstTime
        return Canvas { context, _ in
            guard since > 0, since < 3.2 else { return }
            for piece in confetti {
                let time = since * piece.speedScale
                let x = origin.x + piece.velocity.dx * time + sin(time * piece.flutter + piece.phase) * 14 * time
                let y = origin.y + piece.velocity.dy * time + 0.5 * 980 * time * time
                let fade = 1 - smoothstep(2.2, 3.1, since)
                var piece2D = context
                piece2D.opacity = fade
                piece2D.translateBy(x: x, y: y)
                piece2D.rotate(by: .degrees(time * piece.spin))
                // Turning in 3D: squash one way and back.
                piece2D.scaleBy(x: 1, y: CGFloat(abs(cos(time * piece.flutter))) * 0.8 + 0.2)
                let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height)
                let path = piece.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
                piece2D.fill(path, with: .color(piece.color))
            }
        }
        .allowsHitTesting(false)
    }

    /// The gift tag, rising out of the box with a bounce.
    private func card(t: Double, closing: Double, from boxCenter: CGPoint) -> some View {
        let since = t - cardTime
        let rise = easeOutBack(clamp01(since / 0.65))
        let settle = easeOutElastic(clamp01(since / 1.1))
        let startY = boxCenter.y - 20
        let endY: CGFloat = 228
        let y = startY + (endY - startY) * rise - closing * 50

        return GiftTag(fact: fact, anotherOne: anotherOne, close: dismiss)
            .onHover { isHovering = $0 }
            .scaleEffect((0.15 + 0.85 * rise) * (1 - 0.35 * closing))
            .rotationEffect(.degrees(-14 * (1 - settle)))
            .opacity(clamp01(since / 0.12) * (1 - closing))
            .position(x: boxCenter.x, y: y)
            .allowsHitTesting(since > 0.4 && closingSince == nil)
    }

    private func anotherOne() {
        withAnimation(.smooth(duration: 0.35)) {
            fact = SeasonFacts.next()
        }
    }
}

// MARK: - The card

/// A card in the style of a system notification: material, a symbol tile,
/// and plain system type.
private struct GiftTag: View {
    let fact: SeasonFacts.Fact
    let anotherOne: () -> Void
    let close: () -> Void

    @State private var isHoveringClose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: fact.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.gradient))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Did You Know?")
                        .font(.system(size: 14, weight: .semibold))
                    Text("A present from Santa")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isHoveringClose ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
                .help(Text("Close"))
                .accessibilityLabel(Text("Close"))
            }

            Text(fact.text)
                .font(.system(size: 13))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .id(fact.text)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))

            HStack {
                Spacer()
                Button("Next Fact", action: anotherOne)
                    .controlSize(.regular)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

// MARK: - The box

private let giftRed = Color(red: 0.84, green: 0.13, blue: 0.16)
private let giftGold = Color(red: 0.97, green: 0.77, blue: 0.28)

private struct GiftBox: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [giftRed, Color(red: 0.6, green: 0.06, blue: 0.1)], startPoint: .top, endPoint: .bottom))
            Rectangle()
                .fill(LinearGradient(colors: [giftGold, Color(red: 0.8, green: 0.55, blue: 0.12)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 14)
            // Light catching the left edge.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .leading, endPoint: .center))
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
    }
}

private struct GiftLid: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // The bow.
            HStack(spacing: 0) {
                Ellipse()
                    .fill(giftGold)
                    .frame(width: 28, height: 18)
                    .rotationEffect(.degrees(-22))
                Ellipse()
                    .fill(giftGold)
                    .frame(width: 28, height: 18)
                    .rotationEffect(.degrees(22))
            }
            .overlay(Circle().fill(Color(red: 0.85, green: 0.6, blue: 0.15)).frame(width: 10, height: 10))
            .offset(y: -14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.92, green: 0.2, blue: 0.22), giftRed], startPoint: .top, endPoint: .bottom))
                .frame(height: 16)
                .overlay(Rectangle().fill(giftGold).frame(width: 14))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
    }
}

// MARK: - Confetti

private struct Confetto {
    var velocity: CGVector
    var size: CGSize
    var color: Color
    var isRound: Bool
    var spin: Double
    var flutter: Double
    var phase: Double
    var speedScale: Double

    private static let colors: [Color] = [
        Color(red: 0.9, green: 0.15, blue: 0.2), Color(red: 0.15, green: 0.65, blue: 0.3), Color(red: 0.98, green: 0.78, blue: 0.25),
        .white, Color(red: 0.35, green: 0.6, blue: 1), Color(red: 1, green: 0.55, blue: 0.75),
    ]

    static func burst(count: Int) -> [Confetto] {
        (0..<count).map { _ in
            let angle = Double.random(in: -155 ... -25) * .pi / 180
            let speed = Double.random(in: 320...820)
            let isRound = Double.random(in: 0...1) < 0.3
            let width = Double.random(in: 5...9)
            return Confetto(
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: isRound ? CGSize(width: width * 0.8, height: width * 0.8) : CGSize(width: width, height: width * 0.45),
                color: colors.randomElement() ?? .white,
                isRound: isRound,
                spin: Double.random(in: -720...720),
                flutter: Double.random(in: 5...12),
                phase: Double.random(in: 0...(2 * .pi)),
                speedScale: Double.random(in: 0.85...1.1)
            )
        }
    }
}

// MARK: - Easing

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

private func easeOutBack(_ t: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}

private func easeOutElastic(_ t: Double) -> Double {
    guard t > 0, t < 1 else { return t <= 0 ? 0 : 1 }
    return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * .pi / 3)) + 1
}
