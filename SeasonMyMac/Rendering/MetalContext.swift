import Metal
import OSLog

/// The Metal objects shared by every screen: device, queue, and pipelines.
///
/// Pipelines are expensive to create, so they're built once at launch.
final class MetalContext {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let flakePipeline: MTLRenderPipelineState
    let pilePipeline: MTLRenderPipelineState
    let wirePipeline: MTLRenderPipelineState
    let bulbPipeline: MTLRenderPipelineState
    let snowballPipeline: MTLRenderPipelineState
    let snowmanPipeline: MTLRenderPipelineState
    let sparklePipeline: MTLRenderPipelineState
    let spritePipeline: MTLRenderPipelineState
    let frostPipeline: MTLRenderPipelineState
    /// Pictures of the reindeer, the sleigh and presents.
    let sprites: SpriteAtlas

    /// - Parameter libraryURL: A compiled shader library to use instead of the app's own (for tools).
    init?(libraryURL: URL? = nil) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = libraryURL.flatMap({ try? device.makeLibrary(URL: $0) }) ?? device.makeDefaultLibrary()
        else {
            Logger.rendering.error("Metal is unavailable")
            return nil
        }

        do {
            flakePipeline = try Self.makePipeline(device: device, library: library, name: "flake")
            pilePipeline = try Self.makePipeline(device: device, library: library, name: "pile")
            wirePipeline = try Self.makePipeline(device: device, library: library, name: "wire")
            bulbPipeline = try Self.makePipeline(device: device, library: library, name: "bulb")
            snowballPipeline = try Self.makePipeline(device: device, library: library, name: "snowball")
            snowmanPipeline = try Self.makePipeline(device: device, library: library, name: "snowman")
            sparklePipeline = try Self.makePipeline(device: device, library: library, name: "sparkle")
            spritePipeline = try Self.makePipeline(device: device, library: library, name: "sprite")
            frostPipeline = try Self.makePipeline(device: device, library: library, name: "frost")
        } catch {
            Logger.rendering.error("Failed to build render pipelines: \(error)")
            return nil
        }

        guard let sprites = SpriteAtlas(device: device, commandQueue: commandQueue) else {
            Logger.rendering.error("Couldn't draw the sprite atlas")
            return nil
        }
        self.sprites = sprites
        self.device = device
        self.commandQueue = commandQueue
    }

    /// Builds the pipeline for the `<name>Vertex` / `<name>Fragment` shader pair.
    private static func makePipeline(device: MTLDevice, library: MTLLibrary, name: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = name
        descriptor.vertexFunction = library.makeFunction(name: "\(name)Vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "\(name)Fragment")

        // Shaders output premultiplied alpha, so blend with "source over".
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
