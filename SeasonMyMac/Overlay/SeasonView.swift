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

    /// Snow Play is switched on from the menu bar: the pointer plays with snow
    /// without holding any keys.
    var isPlayModeOn = false

    /// Asks to leave Snow Play (a right-click).
    var onEndPlay: (() -> Void)?
    /// Reports that someone played, so Snow Play doesn't time out.
    var onPlayed: (() -> Void)?

    let display: DisplayInfo
    private let geometry: ScreenGeometry
    private let desktop: DesktopScanner
    private let music: MusicSync
    private let atlas: SpriteAtlas
    private var renderer: SceneRenderer?

    private var snow: SnowWorld
    private var dockLights = LightString()
    private var topLights = LightString()

    private var displayLink: CADisplayLink?
    private var currentFrameRate: Float = 0
    private var lastTimestamp: CFTimeInterval?
    private var elapsed: Float = 0
    private var lastCursor: SIMD2<Float>?

    private var sleigh = Sleigh()
    private var trail: [TrailSparkle] = []
    /// 0...1: frost creeps in slowly after it's turned on.
    private var frostGrowth: Float = 0
    /// Snowfall is turned up to a blizzard until then ("Let It Snow!").
    private var blizzardUntil: Float = 0

    private var acceptsMouse = false
    private var isDragging = false
    private var dragSamples: [(point: SIMD2<Float>, time: CFTimeInterval)] = []

    private var syncedGeneration = -1
    private var needsSurfaceSync = true
    private var needsRedraw = true

    /// The effects are faded out (full screen, or a paused app is in front).
    private var isHidingEffects = false
    private var hiddenSince: CFTimeInterval = 0
    private let fadeDuration: CFTimeInterval = 0.35

    init(screen: NSScreen, metal: MetalContext, desktop: DesktopScanner, music: MusicSync, settings: AppSettings) {
        geometry = ScreenGeometry(screen: screen)
        display = DisplayInfo(screen: screen)
        self.desktop = desktop
        self.music = music
        atlas = metal.sprites
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

        snow.play.throwPower = Float(settings.play.throwPower)
        snow.play.splatsEnabled = settings.play.splats
        snow.play.maxSnowmen = Int(settings.play.maxSnowmen.rounded())

        dockLights.apply(settings.lights)
        dockLights.standsUpright = settings.lights.dockStyle == .rim
        topLights.apply(settings.lights)
        if !settings.lights.dancesToMusic {
            dockLights.music = nil
            topLights.music = nil
        }
        if !settings.extras.frost { frostGrowth = 0 }
        if !settings.extras.sleigh { sleigh.stop() }

        if previous?.snow != settings.snow || previous?.lights != settings.lights {
            needsSurfaceSync = true
        }
        needsRedraw = true
    }

    func shakeOffAllSnow() {
        snow.shakeOffAllSnow()
    }

    // MARK: Winter fun

    /// Drops a snowman onto this screen.
    func buildSnowman() {
        guard settings.snow.isEnabled else { return }
        snow.buildSnowman()
        needsRedraw = true
    }

    /// Melts every snowman, snowball and present.
    func clearPlay() {
        snow.clearPlay()
        needsRedraw = true
    }

    /// Melts every snowman and snowball, quickly, with a little puddle each.
    func meltSnowmen() {
        snow.meltEverything()
        needsRedraw = true
    }

    /// A blizzard for a little while.
    func letItSnow(seconds: Float = 25) {
        blizzardUntil = elapsed + seconds
    }

    /// Whether Santa can fly across this screen.
    var canLaunchSleigh: Bool {
        settings.extras.sleigh && !sleigh.isFlying
    }

    func launchSleigh() {
        guard settings.extras.sleigh else { return }
        let gifts = settings.extras.sleighDropsGifts && settings.snow.isEnabled ? Int.random(in: 1...2) : 0
        sleigh.start(size: geometry.size, topInset: Float(geometry.menuBarHeight), gifts: gifts)
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
        updateMouseCapture()

        if settings.snow.isEnabled {
            let base = Float(settings.snow.intensity)
            snow.intensity = elapsed < blizzardUntil ? max(base, min(1, 0.4 + (blizzardUntil - elapsed) / 8)) : base
            snow.step(dt: dt, cursor: isDragging ? nil : cursor)
        }
        let wind = Float(settings.snow.windDirection) * 20 + sin(elapsed * 0.4) * 6
        if settings.lights.isEnabled, settings.lights.dancesToMusic {
            let pulse = music.pulse()
            dockLights.music = pulse
            topLights.music = pulse
        }
        dockLights.step(dt: dt, time: elapsed, wind: wind, cursor: cursor, cursorVelocity: cursorVelocity)
        topLights.step(dt: dt, time: elapsed, wind: wind, cursor: cursor, cursorVelocity: cursorVelocity)
        stepSleigh(dt: dt)
        if settings.extras.frost { frostGrowth = min(1, frostGrowth + dt / 30) }

        let isStatic = !settings.snow.isEnabled && dockLights.isAtRest && topLights.isAtRest && !sleigh.isFlying && trail.isEmpty && !settings.extras.frost
        if !isStatic || needsRedraw {
            renderer?.render(content, viewportSize: geometry.size)
            needsRedraw = false
        }
        setFrameRate(preferredFrameRate(isStatic: isStatic))
    }

    private var content: SceneContent {
        let play = settings.play
        return SceneContent(
            snow: settings.snow.isEnabled ? snow : nil,
            lights: settings.lights.isEnabled ? [dockLights, topLights] : [],
            bulbSize: settings.lights.bulbPointSize,
            snowmanLook: SnowmanLook(hat: play.hat, scarf: play.scarf, hasArms: play.hasArms, hasCarrotNose: play.hasCarrotNose),
            sprites: sleighSprites,
            sparkles: trailSparkles,
            frost: frostCorners
        )
    }

    // MARK: Sleigh

    private struct TrailSparkle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float
        var lifetime: Float
        var color: SIMD3<Float>
    }

    private func stepSleigh(dt: Float) {
        for event in sleigh.step(dt: dt, size: geometry.size) {
            switch event {
            case .dropGift(let position, let velocity, let style):
                if settings.snow.isEnabled { snow.dropGift(at: position, velocity: velocity, style: style) }
            case .sparkle(let position, let velocity):
                let gold = Float.random(in: 0...1) < 0.7
                let lifetime = Float.random(in: 0.8...1.6)
                trail.append(
                    TrailSparkle(
                        position: position, velocity: velocity, life: lifetime, lifetime: lifetime,
                        color: gold ? SIMD3(1, 0.84, 0.45) : SIMD3(1, 1, 1)))
            }
        }
        for index in trail.indices {
            trail[index].life -= dt
            trail[index].velocity.y += 20 * dt
            trail[index].position += trail[index].velocity * dt
        }
        trail.removeAll { $0.life <= 0 }
    }

    private var trailSparkles: [SparkleInstance] {
        var sparkles = trail.map { sparkle in
            let progress = 1 - sparkle.life / sparkle.lifetime
            return SparkleInstance(
                center: sparkle.position, size: 1.6 + 1.4 * (1 - progress), opacity: min(1, progress * 6) * (1 - progress), color: SIMD4(sparkle.color, 1))
        }
        if sleigh.isFlying {
            // Rudolph's nose.
            let glow = 0.75 + 0.25 * sin(sleigh.time * 9)
            sparkles.append(SparkleInstance(center: sleigh.noseOfLeadReindeer, size: 2.6, opacity: glow, color: SIMD4(1, 0.15, 0.1, 0.4)))
        }
        return sparkles
    }

    private var sleighSprites: [SpriteInstance] {
        guard sleigh.isFlying else { return [] }
        let direction = sleigh.direction
        func sprite(_ kind: SpriteAtlas.Sprite, at center: SIMD2<Float>, size: Float, rotation: Float = 0) -> SpriteInstance {
            let uv = atlas.uv(for: kind)
            let flip: Float = (kind.facesLeft ? direction > 0 : direction < 0) ? 1 : 0
            return SpriteInstance(center: center, size: SIMD2(size, size), uvMin: uv.min, uvMax: uv.max, rotation: rotation, opacity: 1, flip: flip)
        }
        let tilt = sin(sleigh.time * 1.3 + 0.8) * 0.06 * direction
        var sprites = sleigh.reindeer.map { sprite(.reindeer, at: $0, size: 38) }
        sprites.append(sprite(.santa, at: sleigh.position + SIMD2(-direction * 4, -15), size: 26, rotation: tilt))
        sprites.append(sprite(.sleigh, at: sleigh.position, size: 50, rotation: tilt))
        return sprites
    }

    // MARK: Frost

    private var frostCorners: [FrostInstance] {
        guard settings.extras.frost, frostGrowth > 0 else { return [] }
        let size = geometry.size
        let reach = min(size.x, size.y) * Float(0.25 + 0.45 * settings.extras.frostAmount)
        let amount = Float(0.35 + 0.45 * settings.extras.frostAmount) * smoothGrowth
        let corners: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(0, 0), SIMD2(reach, reach)), (SIMD2(size.x, 0), SIMD2(-reach, reach)),
            (SIMD2(0, size.y), SIMD2(reach, -reach)), (SIMD2(size.x, size.y), SIMD2(-reach, -reach)),
        ]
        return corners.enumerated().map { index, corner in
            FrostInstance(corner: corner.0, extent: corner.1, amount: amount, seed: Float(index) * 17.3, time: elapsed)
        }
    }

    private var smoothGrowth: Float {
        frostGrowth * frostGrowth * (3 - 2 * frostGrowth)
    }

    // MARK: Playing with snow

    /// Lets the pointer grab snow while Snow Play is on or the hold keys are down.
    private func updateMouseCapture() {
        let wants = settings.play.isEnabled && (isPlayModeOn || isDragging || settings.play.holdKeys.arePressed)
        guard wants != acceptsMouse else { return }
        acceptsMouse = wants
        window?.ignoresMouseEvents = !wants
        if wants, lastCursor != nil {
            NSCursor.openHand.set()
        } else if !wants {
            NSCursor.arrow.set()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func localPoint(of event: NSEvent) -> SIMD2<Float> {
        let point = convert(event.locationInWindow, from: nil)
        return SIMD2(Float(point.x), Float(bounds.height - point.y))
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsMouse, settings.play.isEnabled else { return }
        onPlayed?()
        let point = localPoint(of: event)
        if sleigh.contains(point), settings.snow.isEnabled {
            // Ho ho ho: a present, right now.
            snow.dropGift(at: sleigh.position + SIMD2(0, 10), velocity: SIMD2(sleigh.direction * 120, -80), style: Int.random(in: 0...3))
            return
        }
        // Double-click a snowman to melt it.
        if event.clickCount >= 2, snow.meltSnowman(at: point) { return }
        if let gift = snow.openGift(at: point) {
            GiftReveal.shared.show(at: screenPoint(fromLocal: gift), on: window?.screen)
            return
        }
        // Shift-drag on a snowman takes its head; otherwise the whole snowman comes along.
        snow.grab(at: point, takingTopBall: event.modifierFlags.contains(.shift))
        isDragging = true
        dragSamples = [(point, event.timestamp)]
        NSCursor.closedHand.set()
    }

    /// A local point (top-left origin) in screen coordinates.
    private func screenPoint(fromLocal point: SIMD2<Float>) -> NSPoint {
        let inView = NSPoint(x: CGFloat(point.x), y: bounds.height - CGFloat(point.y))
        return window?.convertPoint(toScreen: convert(inView, to: nil)) ?? inView
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = localPoint(of: event)
        snow.moveHeld(to: point)
        dragSamples.append((point, event.timestamp))
        dragSamples.removeAll { event.timestamp - $0.time > 0.1 }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        var velocity = SIMD2<Float>.zero
        if let first = dragSamples.first, let last = dragSamples.last, event.timestamp - last.time < 0.05, last.time - first.time > 0.008 {
            velocity = (last.point - first.point) / Float(last.time - first.time)
        }
        snow.release(velocity: velocity)
        dragSamples.removeAll()
        NSCursor.openHand.set()
        onPlayed?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if isPlayModeOn { onEndPlay?() }
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

        if lights.isEnabled, lights.onDock, let garland = dockGarland() {
            dockLights.standsUpright = garland.standsUpright
            dockLights.hang(between: garland.anchors, sag: garland.sag, bulbSpacing: garland.bulbSpacing)
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

    /// Where the string is clipped onto the Dock, in the chosen style.
    private func dockGarland() -> DockGarland.Layout? {
        guard let dock = desktop.dockLayout, dock.isHorizontal else { return nil }
        let frame = geometry.localRect(fromGlobal: dock.frame)
        guard geometry.localBounds.intersects(frame) else { return nil }
        let items = dock.itemFrames.map { geometry.localRect(fromGlobal: $0) }
        return DockGarland.layout(style: settings.lights.dockStyle, frame: frame, items: items, density: settings.lights.density)
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
        // Only the frost glinting: a gentle 15 fps is plenty.
        if !settings.snow.isEnabled, dockLights.isAtRest, topLights.isAtRest, !sleigh.isFlying, trail.isEmpty { return 15 }
        if isLowPowerModeEnabled { return 30 }
        switch settings.performance {
        case .batterySaver: return 30
        case .smooth: return 60
        case .balanced:
            // Drifting snow and twinkling lights look great at 30 fps and cost
            // half as much (for this app *and* the window server). Only fast
            // motion gets 60 fps.
            let isSwinging = dockLights.isSwingingNoticeably || topLights.isSwingingNoticeably
            let isDancing = dockLights.music != nil || topLights.music != nil
            return snow.isAnimatingQuickly || isSwinging || isDancing || sleigh.isFlying || isDragging ? 60 : 30
        }
    }

    private func setFrameRate(_ rate: Float) {
        guard rate != currentFrameRate else { return }
        currentFrameRate = rate
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }
}
