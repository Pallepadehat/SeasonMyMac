import SeasonKit
import SwiftUI

// MARK: - Snow

/// A miniature desktop, with a window and a Dock, where the real snow
/// simulation runs with the current settings. Snow builds up faster here
/// than on the desktop so you can see the effect of the settling options.
struct SnowPreview: View {
    let settings: SnowSettings

    @State private var model = SnowPreviewModel()
    /// Animating costs real CPU, so only do it while Settings is the active window.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        PreviewCard(caption: settings.isEnabled ? "Live preview — try brushing the snow" : "Snow is off") {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !settings.isEnabled || activeState == .inactive)) { timeline in
                Canvas { context, size in
                    model.advance(to: timeline.date, size: size, settings: settings)
                    model.draw(in: &context, size: size)
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    model.cursor = SIMD2(Float(location.x), Float(location.y))
                } else {
                    model.cursor = nil
                }
            }
        }
    }
}

@MainActor
private final class SnowPreviewModel {
    var cursor: SIMD2<Float>?

    private var world: SnowWorld?
    private var size: CGSize = .zero
    private var lastDate: Date?
    private var windowFrame: CGRect = .zero
    private var dockFrame: CGRect = .zero

    func advance(to date: Date, size: CGSize, settings: SnowSettings) {
        if world == nil || size != self.size {
            self.size = size
            windowFrame = CGRect(x: size.width * 0.22, y: size.height * 0.42, width: size.width * 0.5, height: size.height * 0.36)
            dockFrame = CGRect(x: size.width * 0.3, y: size.height - 26, width: size.width * 0.4, height: 22)
            world = SnowWorld(size: SIMD2(Float(size.width), Float(size.height)))
        }
        guard var world else { return }

        var configuration = SnowConfiguration(settings)
        configuration.accumulationRate *= 8  // show settling within seconds
        world.configuration = configuration
        world.intensity = Float(settings.intensity)

        let sources = [
            SurfaceSource(id: .dock, frame: dockFrame, acceptsSnow: settings.settlesOnDock, edgeInset: 4),
            SurfaceSource(id: .window(1), frame: windowFrame, acceptsSnow: settings.settlesOnWindows, edgeInset: 6),
        ]
        let surfaces = SurfaceLayout.surfaces(from: sources, in: CGRect(origin: .zero, size: size), topInset: 0, maxPileHeight: Float(settings.depth))
        world.updateSurfaces(surfaces, sampleInterval: 1.0 / 30)

        let dt = lastDate.map { Float(min(date.timeIntervalSince($0), 1.0 / 15)) } ?? 1.0 / 30
        lastDate = date
        world.step(dt: dt, cursor: cursor)
        self.world = world
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        // A window with traffic lights, and a Dock.
        context.fill(Path(roundedRect: windowFrame, cornerRadius: 8), with: .color(Color(white: 0.17)))
        context.fill(
            Path(roundedRect: windowFrame.insetBy(dx: 0.5, dy: 0.5).divided(atDistance: 18, from: .minYEdge).slice, cornerRadius: 8),
            with: .color(Color(white: 0.22)))
        for (index, color) in [Color.red, .yellow, .green].enumerated() {
            let dot = CGRect(x: windowFrame.minX + 9 + CGFloat(index) * 11, y: windowFrame.minY + 6, width: 7, height: 7)
            context.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.85)))
        }
        context.fill(Path(roundedRect: dockFrame, cornerRadius: 7), with: .color(.white.opacity(0.18)))

        guard let world else { return }

        for pile in world.piles {
            var path = Path()
            path.move(to: CGPoint(x: CGFloat(pile.columnCenter(0)), y: CGFloat(pile.y)))
            for column in 0..<pile.columnCount where pile.isVisible[column] {
                path.addLine(to: CGPoint(x: CGFloat(pile.columnCenter(column)), y: CGFloat(pile.y - pile.displayHeight(ofColumn: column))))
            }
            path.addLine(to: CGPoint(x: CGFloat(pile.columnCenter(pile.columnCount - 1)), y: CGFloat(pile.y)))
            path.closeSubpath()
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [.white, Color(red: 0.8, green: 0.86, blue: 0.96)]),
                    startPoint: CGPoint(x: 0, y: CGFloat(pile.y - 8)),
                    endPoint: CGPoint(x: 0, y: CGFloat(pile.y))
                ))
        }

        for flake in world.flakes {
            let radius = CGFloat(flake.radius)
            let rect = CGRect(x: CGFloat(flake.position.x) - radius, y: CGFloat(flake.position.y) - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(Double(flake.opacity))))
        }
    }
}

// MARK: - Lights

/// A miniature Dock with lights draped over its icons, running the real
/// light simulation. Hover over the bulbs to make them swing.
struct LightsPreview: View {
    let settings: LightSettings

    @State private var model = LightsPreviewModel()
    /// Animating costs real CPU, so only do it while Settings is the active window.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        PreviewCard(caption: settings.isEnabled ? "Live preview — nudge the bulbs" : "Lights are off") {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !settings.isEnabled || activeState == .inactive)) { timeline in
                Canvas { context, size in
                    model.advance(to: timeline.date, size: size, settings: settings)
                    model.draw(in: &context, settings: settings)
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    model.cursor = SIMD2(Float(location.x), Float(location.y))
                } else {
                    model.cursor = nil
                }
            }
        }
    }
}

@MainActor
private final class LightsPreviewModel {
    var cursor: SIMD2<Float>?

    private var lights = LightString()
    private var icons: [CGRect] = []
    private var dock: CGRect = .zero
    private var start = Date()
    private var lastDate: Date?
    private var lastCursor: SIMD2<Float>?

    private static let iconColors: [Color] = [.blue, .gray, .orange, .green, .pink, .purple, .teal, .indigo]

    func advance(to date: Date, size: CGSize, settings: LightSettings) {
        let iconSize: CGFloat = 44
        let count = 7
        let width = CGFloat(count) * (iconSize + 8) + 16
        dock = CGRect(x: (size.width - width) / 2, y: size.height - iconSize - 34, width: width, height: iconSize + 16)
        icons = (0..<count).map { index in
            CGRect(x: dock.minX + 12 + CGFloat(index) * (iconSize + 8), y: dock.minY + 8, width: iconSize, height: iconSize)
        }

        let gaps = zip(icons, icons.dropFirst()).map { ($0.maxX + $1.minX) / 2 }
        let xs = [icons[0].minX - 2] + gaps + [icons[icons.count - 1].maxX + 2]
        let anchors = xs.map { SIMD2(Float($0.rounded()), Float(dock.minY) + 1.5) }
        lights.hang(between: anchors, sag: Float(iconSize) * 0.12, bulbSpacing: 26 / Float(settings.density))
        lights.apply(settings)

        let dt = lastDate.map { Float(min(date.timeIntervalSince($0), 1.0 / 15)) } ?? 1.0 / 30
        lastDate = date
        let velocity = cursor.flatMap { cursor in lastCursor.map { (cursor - $0) / max(dt, 0.001) } } ?? .zero
        lastCursor = cursor
        lights.step(dt: dt, time: Float(date.timeIntervalSince(start)), wind: 0, cursor: cursor, cursorVelocity: velocity)
    }

    func draw(in context: inout GraphicsContext, settings: LightSettings) {
        context.fill(Path(roundedRect: dock, cornerRadius: 16), with: .color(.white.opacity(0.16)))
        for (index, icon) in icons.enumerated() {
            let color = Self.iconColors[index % Self.iconColors.count]
            context.fill(
                Path(roundedRect: icon, cornerRadius: 10),
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.95), color.opacity(0.6)]),
                    startPoint: icon.origin, endPoint: CGPoint(x: icon.maxX, y: icon.maxY)
                ))
        }

        // The wire.
        var wire = Path()
        if let first = lights.wire.first {
            wire.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
            for point in lights.wire.dropFirst() {
                wire.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
            }
        }
        context.stroke(wire, with: .color(Color(red: 0.08, green: 0.2, blue: 0.1)), lineWidth: 1.6)

        let size = CGFloat(settings.bulbPointSize)

        // Glows, softened together in one blurred layer.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: size * 1.6))
            for bulb in lights.bulbs {
                let center = glassCenter(of: bulb, size: size)
                let radius = size * 1.4
                layer.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color(of: bulb).opacity(Double(bulb.brightness) * 0.55))
                )
            }
        }

        // Bulbs and their sockets, swung around the anchor.
        for bulb in lights.bulbs {
            var bulbContext = context
            bulbContext.translateBy(x: CGFloat(bulb.anchor.x), y: CGFloat(bulb.anchor.y))
            bulbContext.rotate(by: .radians(-Double(bulb.angle)))

            let glass = CGRect(x: -size * 0.58, y: size * 0.7, width: size * 1.16, height: size * 2.1)
            let lit = Double(bulb.brightness)
            bulbContext.fill(Path(ellipseIn: glass.offsetBy(dx: 0.5, dy: 1.5)), with: .color(.black.opacity(0.25)))
            bulbContext.fill(
                Path(ellipseIn: glass),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.35 + 0.5 * lit), color(of: bulb).opacity(0.55 + 0.45 * lit)]),
                    center: CGPoint(x: 0, y: size * 1.75), startRadius: 0, endRadius: size * 1.1
                ))
            bulbContext.fill(
                Path(roundedRect: CGRect(x: -size * 0.3, y: -size * 0.06, width: size * 0.6, height: size * 0.96), cornerRadius: size * 0.1),
                with: .color(Color(red: 0.1, green: 0.2, blue: 0.12))
            )
        }
    }

    private func glassCenter(of bulb: LightBulb, size: CGFloat) -> CGPoint {
        let distance = size * 1.75
        let angle = CGFloat(bulb.angle)
        return CGPoint(x: CGFloat(bulb.anchor.x) + sin(angle) * distance, y: CGFloat(bulb.anchor.y) + cos(angle) * distance)
    }

    private func color(of bulb: LightBulb) -> Color {
        Color(red: Double(bulb.color.x), green: Double(bulb.color.y), blue: Double(bulb.color.z))
    }
}
