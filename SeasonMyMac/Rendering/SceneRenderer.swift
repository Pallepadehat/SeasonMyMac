import CoreGraphics
import Metal
import QuartzCore
import SeasonKit

/// Everything one screen draws in a frame.
struct SceneContent {
    var snow: SnowWorld?
    var lights: [LightString]
    /// Radius of a bulb's glass, in points.
    var bulbSize: Float
    var snowmanLook = SnowmanLook()
    /// Extra pictures, like Santa's sleigh, drawn in front of the snow.
    var sprites: [SpriteInstance] = []
    /// Extra sparkles, like the sleigh's trail.
    var sparkles: [SparkleInstance] = []
    var frost: [FrostInstance] = []
}

/// How snowmen are dressed.
struct SnowmanLook {
    var hat = SnowmanHat.random
    var scarf = ScarfColor.random
    var hasArms = true
    var hasCarrotNose = true

    static let scarfColors: [SIMD3<Float>] = [SIMD3(0.82, 0.12, 0.14), SIMD3(0.12, 0.55, 0.25), SIMD3(0.2, 0.42, 0.85), SIMD3(0.95, 0.7, 0.15)]

    func hatNumber(style: UInt32) -> Float {
        switch hat {
        case .random: Float(style % 3 + 1)
        case .topHat: 1
        case .santaHat: 2
        case .beanie: 3
        case .none: 0
        }
    }

    func scarfColor(style: UInt32) -> SIMD4<Float> {
        let colors = Self.scarfColors
        let color: SIMD3<Float>? =
            switch scarf {
            case .random: colors[Int(style / 3 % UInt32(colors.count))]
            case .red: colors[0]
            case .green: colors[1]
            case .blue: colors[2]
            case .gold: colors[3]
            case .none: nil
            }
        return color.map { SIMD4($0, 1) } ?? .zero
    }
}

/// Draws a ``SceneContent`` into a transparent `CAMetalLayer`.
///
/// A frame is at most four instanced draw calls (snow piles, wire, bulbs,
/// flakes, back to front). Instance data lives in a small ring of reusable
/// buffers, so nothing is allocated per frame and the CPU never waits for the GPU.
final class SceneRenderer {
    /// Frames the CPU may prepare while the GPU is still busy with earlier ones.
    private static let framesInFlight = 3

    private let context: MetalContext
    private let layer: CAMetalLayer
    private let frames: [FrameBuffers]
    private let inFlight = DispatchSemaphore(value: framesInFlight)
    private var frameIndex = 0

    /// Lets us skip presenting when the previous frame was already blank.
    private var lastFrameWasEmpty = false

    init(context: MetalContext, layer: CAMetalLayer) {
        self.context = context
        self.layer = layer
        frames = (0..<Self.framesInFlight).map { _ in FrameBuffers(device: context.device, atlas: context.sprites) }

        layer.device = context.device
        layer.pixelFormat = MetalContext.pixelFormat
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
    }

    func render(_ content: SceneContent, viewportSize: SIMD2<Float>) {
        // If the GPU is still busy with every buffer, drop this frame instead of blocking.
        guard inFlight.wait(timeout: .now()) == .success else { return }

        let frame = frames[frameIndex]
        frameIndex = (frameIndex + 1) % frames.count

        let counts = frame.write(content)
        let isEmpty = counts.isEmpty
        defer { lastFrameWasEmpty = isEmpty }

        guard
            !(isEmpty && lastFrameWasEmpty),
            let drawable = layer.nextDrawable(),
            let commandBuffer = context.commandQueue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }

        encode(frame: frame, counts: counts, into: drawable.texture, viewportSize: viewportSize, commandBuffer: commandBuffer)

        commandBuffer.addCompletedHandler { [inFlight] _ in
            inFlight.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Draws `content` into a new image instead of the layer. For previews and tools.
    func snapshot(_ content: SceneContent, viewportSize: SIMD2<Float>, scale: Float = 2) -> CGImage? {
        let width = Int(viewportSize.x * scale), height = Int(viewportSize.y * scale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MetalContext.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor), let commandBuffer = context.commandQueue.makeCommandBuffer() else { return nil }

        let frame = frames[0]
        let counts = frame.write(content)
        encode(frame: frame, counts: counts, into: texture, viewportSize: viewportSize, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func encode(frame: FrameBuffers, counts: FrameBuffers.Counts, into texture: MTLTexture, viewportSize: SIMD2<Float>, commandBuffer: MTLCommandBuffer)
    {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            var uniforms = SceneUniforms(viewportSize: viewportSize)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)

            func draw(_ pipeline: MTLRenderPipelineState, _ buffer: MTLBuffer, vertices: Int, instances: Int) {
                guard instances > 0 else { return }
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices, instanceCount: instances)
            }

            draw(context.pilePipeline, frame.pileSegments.buffer, vertices: 10, instances: counts.pileSegments)
            draw(context.wirePipeline, frame.wireSegments.buffer, vertices: 4, instances: counts.wireSegments)
            draw(context.bulbPipeline, frame.bulbs.buffer, vertices: 4, instances: counts.bulbs)
            draw(context.snowmanPipeline, frame.snowmen.buffer, vertices: 4, instances: counts.snowmen)
            draw(context.snowballPipeline, frame.snowballs.buffer, vertices: 4, instances: counts.snowballs)
            if counts.sprites > 0 {
                encoder.setFragmentTexture(context.sprites.texture, index: 0)
                draw(context.spritePipeline, frame.sprites.buffer, vertices: 4, instances: counts.sprites)
            }
            draw(context.flakePipeline, frame.flakes.buffer, vertices: 4, instances: counts.flakes)
            draw(context.sparklePipeline, frame.sparkles.buffer, vertices: 4, instances: counts.sparkles)
            draw(context.frostPipeline, frame.frost.buffer, vertices: 4, instances: counts.frost)
            encoder.endEncoding()
        }
    }

    /// Presents one transparent frame so nothing lingers on screen.
    func clear(viewportSize: SIMD2<Float>) {
        render(SceneContent(snow: nil, lights: [], bulbSize: 0), viewportSize: viewportSize)
    }
}

// MARK: - Per-frame buffers

/// The instance buffers for one frame in flight.
private final class FrameBuffers {
    struct Counts {
        var flakes = 0
        var pileSegments = 0
        var wireSegments = 0
        var bulbs = 0
        var snowmen = 0
        var snowballs = 0
        var sprites = 0
        var sparkles = 0
        var frost = 0

        var isEmpty: Bool { flakes + pileSegments + wireSegments + bulbs + snowmen + snowballs + sprites + sparkles + frost == 0 }
    }

    let flakes: InstanceBuffer<FlakeInstance>
    let pileSegments: InstanceBuffer<PileSegment>
    let wireSegments: InstanceBuffer<WireSegment>
    let bulbs: InstanceBuffer<BulbInstance>
    let snowmen: InstanceBuffer<SnowmanInstance>
    let snowballs: InstanceBuffer<SnowballInstance>
    let sprites: InstanceBuffer<SpriteInstance>
    let sparkles: InstanceBuffer<SparkleInstance>
    let frost: InstanceBuffer<FrostInstance>
    private let atlas: SpriteAtlas

    init(device: MTLDevice, atlas: SpriteAtlas) {
        self.atlas = atlas
        flakes = InstanceBuffer(device: device, capacity: 2048)
        pileSegments = InstanceBuffer(device: device, capacity: 2048)
        wireSegments = InstanceBuffer(device: device, capacity: 256)
        bulbs = InstanceBuffer(device: device, capacity: 128)
        snowmen = InstanceBuffer(device: device, capacity: 16)
        snowballs = InstanceBuffer(device: device, capacity: 64)
        sprites = InstanceBuffer(device: device, capacity: 32)
        sparkles = InstanceBuffer(device: device, capacity: 256)
        frost = InstanceBuffer(device: device, capacity: 4)
    }

    func write(_ content: SceneContent) -> Counts {
        var counts = Counts()
        if let snow = content.snow {
            counts.flakes = writeFlakes(snow.flakes)
            counts.pileSegments = writePileSegments(for: snow.piles)
        }
        counts.wireSegments = writeWires(for: content.lights)
        counts.bulbs = writeBulbs(for: content.lights, size: content.bulbSize)
        if let snow = content.snow {
            counts.snowmen = writeSnowmen(snow.snowmen, look: content.snowmanLook)
            counts.snowballs = writeSnowballs(snow)
        }
        counts.sprites = writeSprites(gifts: content.snow?.snowballs ?? [], lifetime: content.snow?.play.giftLifetime ?? 0, extra: content.sprites)
        counts.sparkles = writeSparkles(content.snow?.sparkles ?? [], extra: content.sparkles)
        counts.frost = copy(content.frost, into: frost)
        return counts
    }

    private func writeSnowmen(_ source: [Snowman], look: SnowmanLook) -> Int {
        let destination = snowmen.reserve(source.count)
        for (index, man) in source.enumerated() {
            let radii = man.displayRadii
            let melted = 1 - min(1, max(0, man.melt) / 0.3)
            destination[index] = SnowmanInstance(
                base: man.base,
                tilt: man.tilt,
                decorations: man.completedAge < 0 ? 0 : min(1, man.completedAge / 0.45) * melted,
                radii: SIMD4(radii[0], radii.count > 1 ? radii[1] : 0, radii.count > 2 ? radii[2] : 0, Float(radii.count)),
                scarf: look.scarfColor(style: man.style),
                hat: look.hatNumber(style: man.style),
                arms: look.hasArms ? 1 : 0,
                nose: look.hasCarrotNose ? 1 : 0,
                opacity: min(1, man.age * 6 + 0.3)
            )
        }
        return source.count
    }

    /// Snowballs first, then splats on top of them.
    private func writeSnowballs(_ snow: SnowWorld) -> Int {
        let destination = snowballs.reserve(snow.snowballs.count + snow.splats.count)
        var count = 0
        for ball in snow.snowballs where !ball.isGift {
            destination[count] = SnowballInstance(
                center: ball.position, radius: ball.radius, rotation: ball.rotation, squash: ball.squash, opacity: 1, seed: Float(ball.id % 97), kind: 0)
            count += 1
        }
        for splat in snow.splats {
            destination[count] = SnowballInstance(
                center: splat.position, radius: splat.radius, rotation: atan2(-splat.normal.y, splat.normal.x), squash: 0, opacity: splat.opacity,
                seed: splat.seed, kind: 1)
            count += 1
        }
        return count
    }

    private func writeSprites(gifts: [Snowball], lifetime: Float, extra: [SpriteInstance]) -> Int {
        let giftCount = gifts.lazy.filter(\.isGift).count
        let destination = sprites.reserve(giftCount + extra.count)
        var count = 0
        let uv = atlas.uv(for: .gift)
        for gift in gifts where gift.isGift {
            let size = gift.radius * 2.6
            destination[count] = SpriteInstance(
                center: gift.position - SIMD2(0, gift.radius * 0.2), size: SIMD2(size, size * (1 - gift.squash * 0.6)), uvMin: uv.min, uvMax: uv.max,
                rotation: gift.state == .resting ? 0 : sin(gift.age * 6) * 0.25, opacity: gift.opacity(lifetime: lifetime), flip: 0)
            count += 1
        }
        for sprite in extra {
            destination[count] = sprite
            count += 1
        }
        return count
    }

    private func writeSparkles(_ source: [Sparkle], extra: [SparkleInstance]) -> Int {
        let destination = sparkles.reserve(source.count + extra.count)
        var count = 0
        for sparkle in source {
            destination[count] = SparkleInstance(center: sparkle.position, size: sparkle.size, opacity: sparkle.opacity, color: SIMD4(sparkle.color, 1))
            count += 1
        }
        for sparkle in extra {
            destination[count] = sparkle
            count += 1
        }
        return count
    }

    private func copy<Element>(_ source: [Element], into buffer: InstanceBuffer<Element>) -> Int {
        let destination = buffer.reserve(source.count)
        for (index, element) in source.enumerated() {
            destination[index] = element
        }
        return source.count
    }

    private func writeFlakes(_ source: [Flake]) -> Int {
        let destination = flakes.reserve(source.count)
        for (index, flake) in source.enumerated() {
            destination[index] = FlakeInstance(center: flake.position, radius: flake.radius, opacity: flake.opacity)
        }
        return source.count
    }

    private func writePileSegments(for piles: [SnowPile]) -> Int {
        let capacity = piles.reduce(0) { $0 + $1.columnCount }
        let destination = pileSegments.reserve(capacity)
        var count = 0

        for pile in piles {
            var leftHeight = pile.columnCount > 0 ? pile.displayHeight(ofColumn: 0) : 0
            for column in 0..<max(0, pile.columnCount - 1) {
                let next = column + 1
                let rightHeight = pile.displayHeight(ofColumn: next)
                defer { leftHeight = rightHeight }

                guard
                    pile.isVisible[column], pile.isVisible[next],
                    leftHeight > 0.05 || rightHeight > 0.05
                else { continue }

                destination[count] = PileSegment(
                    start: SIMD2(pile.columnCenter(column), pile.y - leftHeight),
                    end: SIMD2(pile.columnCenter(next), pile.y - rightHeight),
                    baseY: pile.y,
                    opacity: 0.97
                )
                count += 1
            }
        }
        return count
    }

    /// Writes each wire's shadow, then the wire, then a little clip at each anchor.
    private func writeWires(for strings: [LightString]) -> Int {
        let capacity = strings.reduce(0) { $0 + 2 * max(0, $1.wire.count - 1) + $1.anchors.count * 2 }
        let destination = wireSegments.reserve(capacity)
        var count = 0
        func append(_ segment: WireSegment) {
            destination[count] = segment
            count += 1
        }

        for string in strings {
            for (start, end) in zip(string.wire, string.wire.dropFirst()) {
                append(WireSegment(start: start, end: end, width: 1.5, isShadow: 1))
            }
        }
        for string in strings {
            for (start, end) in zip(string.wire, string.wire.dropFirst()) {
                append(WireSegment(start: start, end: end, width: 1.5))
            }
            for anchor in string.anchors {
                append(WireSegment(start: anchor - SIMD2(1.2, 0), end: anchor + SIMD2(1.2, 0), width: 3.4))
            }
        }
        return count
    }

    private func writeBulbs(for strings: [LightString], size: Float) -> Int {
        let capacity = strings.reduce(0) { $0 + $1.bulbs.count }
        let destination = bulbs.reserve(capacity)
        var count = 0
        for string in strings {
            for bulb in string.bulbs {
                destination[count] = BulbInstance(
                    anchor: bulb.anchor,
                    angle: bulb.angle,
                    size: size,
                    color: SIMD4(bulb.color, bulb.brightness)
                )
                count += 1
            }
        }
        return count
    }
}

/// A shared-memory Metal buffer that grows when it needs more room.
private final class InstanceBuffer<Element> {
    private let device: MTLDevice
    private(set) var buffer: MTLBuffer
    private var capacity: Int

    init(device: MTLDevice, capacity: Int) {
        self.device = device
        self.capacity = capacity
        buffer = Self.makeBuffer(device: device, capacity: capacity)
    }

    /// Makes room for `count` elements and returns a pointer for writing them.
    func reserve(_ count: Int) -> UnsafeMutablePointer<Element> {
        if count > capacity {
            capacity = max(count, capacity * 2)
            buffer = Self.makeBuffer(device: device, capacity: capacity)
        }
        return buffer.contents().bindMemory(to: Element.self, capacity: capacity)
    }

    private static func makeBuffer(device: MTLDevice, capacity: Int) -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: capacity * MemoryLayout<Element>.stride, options: .storageModeShared) else {
            fatalError("Couldn't allocate a \(capacity)-element Metal buffer")
        }
        return buffer
    }
}
