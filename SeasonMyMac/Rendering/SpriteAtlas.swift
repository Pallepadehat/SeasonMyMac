import AppKit
import Metal

/// A texture holding the few pictures the scene draws as sprites: the
/// reindeer, the sleigh, Santa, and a present. Drawn once at launch from the
/// system's emoji, which look right at any size and in any appearance.
final class SpriteAtlas {
    enum Sprite: Int, CaseIterable {
        case reindeer, sleigh, santa, gift

        var emoji: String {
            switch self {
            case .reindeer: "🦌"
            case .sleigh: "🛷"
            case .santa: "🎅"
            case .gift: "🎁"
            }
        }

        /// Whether the emoji faces left, so it has to be mirrored to fly right.
        var facesLeft: Bool {
            switch self {
            case .reindeer, .sleigh: true
            case .santa, .gift: false
            }
        }
    }

    private static let cellSize = 128
    private static let columns = 4

    let texture: MTLTexture

    init?(device: MTLDevice, commandQueue: MTLCommandQueue) {
        let rows = (Sprite.allCases.count + Self.columns - 1) / Self.columns
        let width = Self.cellSize * Self.columns
        let height = Self.cellSize * rows

        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Top-left origin, like the texture.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for sprite in Sprite.allCases {
            let cell = Self.cellRect(for: sprite)
            let font = NSFont.systemFont(ofSize: CGFloat(Self.cellSize) * 0.78)
            let text = NSAttributedString(string: sprite.emoji, attributes: [.font: font])
            let size = text.size()
            text.draw(at: CGPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor), let data = context.data else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)

        if let commands = commandQueue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
        }
        self.texture = texture
    }

    private static func cellRect(for sprite: Sprite) -> CGRect {
        let column = sprite.rawValue % columns
        let row = sprite.rawValue / columns
        return CGRect(x: column * cellSize, y: row * cellSize, width: cellSize, height: cellSize)
    }

    /// The sprite's corner coordinates in the texture, 0...1.
    func uv(for sprite: Sprite) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        let rect = Self.cellRect(for: sprite)
        let size = SIMD2(Float(texture.width), Float(texture.height))
        return (SIMD2(Float(rect.minX), Float(rect.minY)) / size, SIMD2(Float(rect.maxX), Float(rect.maxY)) / size)
    }
}
