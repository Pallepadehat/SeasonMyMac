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

    init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary()
        else {
            Logger.rendering.error("Metal is unavailable")
            return nil
        }

        do {
            flakePipeline = try Self.makePipeline(device: device, library: library, name: "flake")
            pilePipeline = try Self.makePipeline(device: device, library: library, name: "pile")
            wirePipeline = try Self.makePipeline(device: device, library: library, name: "wire")
            bulbPipeline = try Self.makePipeline(device: device, library: library, name: "bulb")
        } catch {
            Logger.rendering.error("Failed to build render pipelines: \(error)")
            return nil
        }

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
