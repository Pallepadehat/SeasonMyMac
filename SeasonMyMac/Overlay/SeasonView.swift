import AppKit
import QuartzCore
import SeasonKit

/// Runs and draws everything seasonal on one screen: snow, the lights along
/// the Dock, and the lights along the top of the screen.
///
/// The view is backed by a `CAMetalLayer` and driven by the screen's display
/// link. Its frame rate follows what's on screen: 30 fps for drifting snow,
/// 60 fps for fast motion, and a trickle when nothing moves or the effects
/// are hidden.
final class SeasonView: NSView {
    var settings: AppSettings {
        didSet { apply(settings, previous: oldValue) }
    }

    /// Low Power Mode is on: never go above 30 fps.
    var isLowPowerModeEnabled = false

    private let geometry: ScreenGeometry
    private let desktop: DesktopScanner
    private var renderer: SceneRenderer?

    private var snow: SnowWorld
    private var dockLights = LightString()
    private var topLights = LightString()

    private var displayLink: CADisplayLink?
    private var currentFrameRate: Float = 0
    private var lastTimestamp: CFTimeInterval?
    private var elapsed: Float = 0
    private var lastCursor: SIMD2<Float>?

    private var syncedGeneration = -1
    private var needsSurfaceSync = true
    private var needsRedraw = true

    /// The effects are faded out (full screen, or a paused app is in front).
    private var isHidingEffects = false
    private var hiddenSince: CFTimeInterval = 0
    private let fadeDuration: CFTimeInterval = 0.35

    init(screen: NSScreen, metal: MetalContext, desktop: DesktopScanner, settings: AppSettings) {
        geometry = ScreenGeometry(screen: screen)
        self.desktop = desktop
        self.settings = settings
        snow = SnowWorld(size: geometry.size, configuration: SnowConfiguration(settings.snow))

        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        renderer = SceneRenderer(context: metal, layer: metalLayer)
        apply(settings, previous: nil)
        snow.prewarm()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Settings

    private func apply(_ settings: AppSettings, previous: AppSettings?) {
        let snowSettings = settings.snow
        if snowSettings.isEnabled {
            snow.configuration = SnowConfiguration(snowSettings)
            snow.intensity = Float(snowSettings.intensity)
            if previous?.snow.isEnabled == false {
                snow = SnowWorld(size: geometry.size, configuration: SnowConfiguration(snowSettings))
                snow.intensity = Float(snowSettings.intensity)
            }
        }

        dockLights.apply(settings.lights)
        topLights.apply(settings.lights)

        if previous?.snow != settings.snow || previous?.lights != settings.lights {
            needsSurfaceSync = true
        }
        needsRedraw = true
    }

    func shakeOffAllSnow() {
        snow.shakeOffAllSnow()
    }

    // MARK: Layer

    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    private var metalLayer: CAMetalLayer {
        // makeBackingLayer() guarantees the type.
        layer as! CAMetalLayer
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        needsRedraw = true
    }

    // MARK: Running

    func start() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil
        currentFrameRate = 0
        setFrameRate(30)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        // Clamp the time step so a hiccup doesn't teleport flakes through surfaces.
        let dt = lastTimestamp.map { Float(min(link.timestamp - $0, 1.0 / 20)) } ?? 1.0 / 30
        lastTimestamp = link.timestamp
        elapsed += dt

        // Nothing to do while the overlay can't be seen at all, for example on
        // a full-screen app's Space. macOS reports that through occlusion.
        // (While we've faded the effects out ourselves, keep checking so they
        // can fade back in.)
        guard isHidingEffects || window?.occlusionState.contains(.visible) == true else {
            setFrameRate(10)
            return
        }

        desktop.refreshIfNeeded(at: link.timestamp, includeDock: settings.needsDock)

        guard updateVisibility(at: link.timestamp) else {
            setFrameRate(10)  // just keep an eye out for when to come back
            return
        }

        syncWithDesktopIfNeeded()

        let cursor = desktop.cursorLocation(on: geometry)
        let cursorVelocity = cursor.flatMap { cursor in lastCursor.map { (cursor - $0) / dt } } ?? .zero
        lastCursor = cursor

        if settings.snow.isEnabled {
            snow.step(dt: dt, cursor: cursor)
        }
        let wind = Float(settings.snow.windDirection) * 20 + sin(elapsed * 0.4) * 6
        dockLights.step(dt: dt, time: elapsed, wind: wind, cursor: cursor, cursorVelocity: cursorVelocity)
        topLights.step(dt: dt, time: elapsed, wind: wind, cursor: cursor, cursorVelocity: cursorVelocity)

        let isStatic = !settings.snow.isEnabled && dockLights.isAtRest && topLights.isAtRest
        if !isStatic || needsRedraw {
            renderer?.render(content, viewportSize: geometry.size)
            needsRedraw = false
        }
        setFrameRate(preferredFrameRate(isStatic: isStatic))
    }

    private var content: SceneContent {
        SceneContent(
            snow: settings.snow.isEnabled ? snow : nil,
            lights: settings.lights.isEnabled ? [dockLights, topLights] : [],
            bulbSize: settings.lights.bulbPointSize
        )
    }

    // MARK: Desktop

    private func syncWithDesktopIfNeeded() {
        guard needsSurfaceSync || desktop.generation != syncedGeneration else { return }
        syncedGeneration = desktop.generation
        needsSurfaceSync = false
        needsRedraw = true

        if settings.snow.isEnabled {
            let surfaces = desktop.surfaces(on: geometry, settings: settings.snow, maxPileHeight: snow.configuration.maxPileHeight)
            snow.updateSurfaces(surfaces, sampleInterval: desktop.lastSampleInterval, keeping: desktop.hiddenSurfaceIDs)
        }
        hangLights()
    }

    /// Clips the strings up like a real garland: shallow scallops hooked
    /// along the Dock's rim and along the bottom edge of the menu bar.
    private func hangLights() {
        let lights = settings.lights
        let spacing = 26 / Float(lights.density)

        if lights.isEnabled, lights.onDock, let anchors = dockAnchors() {
            dockLights.hang(between: anchors.points, sag: anchors.sag, bulbSpacing: spacing)
        } else {
            dockLights.removeAll()
        }

        if lights.isEnabled, lights.alongTop, lights.topOnAllDisplays || geometry.isMainDisplay {
            let y = Float(geometry.menuBarHeight) + 0.5
            let span = Float(lights.topLoopWidth)
            let count = Int((geometry.size.x + 2 * span) / span)
            let anchors = (0...count).map { SIMD2(-span + Float($0) * span, y) }
            topLights.hang(between: anchors, sag: Float(lights.topDroop), bulbSpacing: spacing)
        } else {
            topLights.removeAll()
        }
    }

    /// Hooks along the Dock's top rim, one in each gap between icons, so the
    /// wire scallops gently over the top of every icon.
    private func dockAnchors() -> (points: [SIMD2<Float>], sag: Float)? {
        guard let dock = desktop.dockLayout, dock.isHorizontal else { return nil }
        let frame = geometry.localRect(fromGlobal: dock.frame)
        guard geometry.localBounds.intersects(frame) else { return nil }

        // Snap to whole points so sub-point jitter in the Dock's layout never
        // nudges the string.
        let items = dock.itemFrames.map { geometry.localRect(fromGlobal: $0) }
        let y = Float(frame.minY.rounded()) + 1.5
        let xs: [CGFloat]
        if items.count >= 2 {
            let gaps = zip(items, items.dropFirst()).map { ($0.maxX + $1.minX) / 2 }
            xs = [max(frame.minX + 14, items[0].minX - 2)] + gaps + [min(frame.maxX - 14, items[items.count - 1].maxX + 2)]
        } else {
            let span: CGFloat = 56
            let count = max(2, Int(frame.width / span))
            xs = (0...count).map { frame.minX + 14 + (frame.width - 28) * CGFloat($0) / CGFloat(count) }
        }

        let iconWidth = Float(items.first?.width ?? 48)
        return (xs.map { SIMD2(Float($0.rounded()), y) }, max(4, iconWidth * 0.12))
    }

    // MARK: Visibility

    /// Fades the effects out and back in. Returns `false` once they're fully hidden.
    private func updateVisibility(at time: CFTimeInterval) -> Bool {
        let shouldHide = desktop.shouldHideEffects(on: geometry, visibility: settings.visibility)
        if shouldHide != isHidingEffects {
            isHidingEffects = shouldHide
            hiddenSince = time
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                window?.animator().alphaValue = shouldHide ? 0 : 1
            }
            if !shouldHide {
                needsSurfaceSync = true
                needsRedraw = true
            }
        }
        return !(isHidingEffects && time - hiddenSince > fadeDuration)
    }

    // MARK: Frame rate

    private func preferredFrameRate(isStatic: Bool) -> Float {
        if isStatic { return 10 }
        if isLowPowerModeEnabled { return 30 }
        switch settings.performance {
        case .batterySaver: return 30
        case .smooth: return 60
        case .balanced:
            // Drifting snow and twinkling lights look great at 30 fps and cost
            // half as much (for this app *and* the window server). Only fast
            // motion gets 60 fps.
            let isSwinging = dockLights.isSwingingNoticeably || topLights.isSwingingNoticeably
            return snow.isAnimatingQuickly || isSwinging ? 60 : 30
        }
    }

    private func setFrameRate(_ rate: Float) {
        guard rate != currentFrameRate else { return }
        currentFrameRate = rate
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }
}
