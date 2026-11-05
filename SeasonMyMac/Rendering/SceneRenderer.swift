import Metal
import QuartzCore
import SeasonKit

/// Everything one screen draws in a frame.
struct SceneContent {
    var snow: SnowWorld?
    var lights: [LightString]
    /// Radius of a bulb's glass, in points.
    var bulbSize: Float
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
        frames = (0..<Self.framesInFlight).map { _ in FrameBuffers(device: context.device) }

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

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
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
            draw(context.flakePipeline, frame.flakes.buffer, vertices: 4, instances: counts.flakes)
            encoder.endEncoding()
        }

        commandBuffer.addCompletedHandler { [inFlight] _ in
            inFlight.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
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

        var isEmpty: Bool { flakes + pileSegments + wireSegments + bulbs == 0 }
    }

    let flakes: InstanceBuffer<FlakeInstance>
    let pileSegments: InstanceBuffer<PileSegment>
    let wireSegments: InstanceBuffer<WireSegment>
    let bulbs: InstanceBuffer<BulbInstance>

    init(device: MTLDevice) {
        flakes = InstanceBuffer(device: device, capacity: 2048)
        pileSegments = InstanceBuffer(device: device, capacity: 2048)
        wireSegments = InstanceBuffer(device: device, capacity: 256)
        bulbs = InstanceBuffer(device: device, capacity: 128)
    }

    func write(_ content: SceneContent) -> Counts {
        var counts = Counts()
        if let snow = content.snow {
            counts.flakes = writeFlakes(snow.flakes)
            counts.pileSegments = writePileSegments(for: snow.piles)
        }
        counts.wireSegments = writeWires(for: content.lights)
        counts.bulbs = writeBulbs(for: content.lights, size: content.bulbSize)
        return counts
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
