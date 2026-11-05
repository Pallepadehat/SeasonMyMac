#!/usr/bin/env swift  // Draws the SeasonMyMac app icon and logo.
//
//   swift scripts/generate-icon.swift
//
// Writes every size the asset catalog needs, plus docs/logo.png. The artwork
// follows Apple's macOS icon grid: an 824 × 824 pt rounded square centred on a
// 1024 × 1024 pt canvas, with a soft drop shadow.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon into a 1024 × 1024 context with a top-left origin.
func drawIcon(in context: CGContext) {
    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Drop shadow under the whole tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x101633))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // Night sky.
    let sky = CGGradient(colorsSpace: nil, colors: [color(0x0B1033), color(0x1E2A78), color(0x3B3F9E)] as CFArray, locations: [0, 0.65, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: body.maxY), options: [])

    // A soft glow behind the snowflake.
    let glow = CGGradient(colorsSpace: nil, colors: [color(0x8FB4FF, 0.45), color(0x8FB4FF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 565), startRadius: 0, endCenter: CGPoint(x: 512, y: 565), endRadius: 300, options: [])

    // Stars.
    let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (210, 360, 5), (300, 300, 3), (780, 340, 4), (840, 450, 3), (190, 520, 3), (720, 610, 3), (260, 640, 4), (860, 600, 4),
    ]
    context.setFillColor(color(0xFFFFFF, 0.8))
    for (x, y, r) in stars {
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // The snowflake: six arms, each with two pairs of branches, drawn as
    // vector strokes so it stays crisp at every size.
    let center = CGPoint(x: 512, y: 565)
    let flake = CGMutablePath()
    for arm in 0..<6 {
        let angle = CGFloat(arm) * .pi / 3 - .pi / 2
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        func along(_ distance: CGFloat) -> CGPoint {
            CGPoint(x: center.x + direction.x * distance, y: center.y + direction.y * distance)
        }
        flake.move(to: center)
        flake.addLine(to: along(172))
        for (distance, length) in [(88, 52), (134, 37)] as [(CGFloat, CGFloat)] {
            let base = along(distance)
            for side in [-1.0, 1.0] as [CGFloat] {
                let branchAngle = angle + side * .pi / 4
                flake.move(to: base)
                flake.addLine(to: CGPoint(x: base.x + cos(branchAngle) * length, y: base.y + sin(branchAngle) * length))
            }
        }
    }
    context.saveGState()
    context.setShadow(offset: .zero, blur: 46, color: color(0xA9C8FF, 0.95))
    context.addPath(flake)
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineWidth(26)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // Snowy hills.
    let farHill = CGMutablePath()
    farHill.move(to: CGPoint(x: body.minX, y: 790))
    farHill.addCurve(to: CGPoint(x: body.maxX, y: 760), control1: CGPoint(x: 360, y: 700), control2: CGPoint(x: 700, y: 820))
    farHill.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
    farHill.addLine(to: CGPoint(x: body.minX, y: body.maxY))
    farHill.closeSubpath()
    context.addPath(farHill)
    context.setFillColor(color(0xBFD2F5))
    context.fillPath()

    let nearHill = CGMutablePath()
    nearHill.move(to: CGPoint(x: body.minX, y: 850))
    nearHill.addCurve(to: CGPoint(x: body.maxX, y: 820), control1: CGPoint(x: 420, y: 770), control2: CGPoint(x: 640, y: 900))
    nearHill.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
    nearHill.addLine(to: CGPoint(x: body.minX, y: body.maxY))
    nearHill.closeSubpath()
    context.saveGState()
    context.addPath(nearHill)
    context.clip()
    let snow = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF), color(0xDCE7FA)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(snow, start: CGPoint(x: 512, y: 780), end: CGPoint(x: 512, y: body.maxY), options: [])
    context.restoreGState()

    // A garland of lights across the top, clipped up in three loops.
    let clips: [CGPoint] = [CGPoint(x: 70, y: 196), CGPoint(x: 365, y: 196), CGPoint(x: 659, y: 196), CGPoint(x: 954, y: 196)]
    let sag: CGFloat = 70
    func pointOnWire(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + sag * 4 * t * (1 - t))
    }

    let wire = CGMutablePath()
    wire.move(to: clips[0])
    for (a, b) in zip(clips, clips.dropFirst()) {
        for step in 1...24 {
            wire.addLine(to: pointOnWire(a, b, CGFloat(step) / 24))
        }
    }
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 6), blur: 8, color: color(0x000000, 0.4))
    context.addPath(wire)
    context.setStrokeColor(color(0x123D1F))
    context.setLineWidth(9)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()

    let bulbColors: [UInt32] = [0xF2352E, 0x2BC04F, 0xFFB72E, 0x3A7BFF]
    var bulbIndex = 0
    for (a, b) in zip(clips, clips.dropFirst()) {
        for t in [0.25, 0.5, 0.75] as [CGFloat] {
            let anchor = pointOnWire(a, b, t)
            let hue = bulbColors[bulbIndex % bulbColors.count]
            let tilt = CGFloat([-0.12, 0.08, -0.05, 0.14, -0.1, 0.06, 0.1, -0.08, 0.04][bulbIndex % 9])
            bulbIndex += 1

            context.saveGState()
            context.translateBy(x: anchor.x, y: anchor.y)
            context.rotate(by: tilt)

            // Glow.
            let halo = CGGradient(colorsSpace: nil, colors: [color(hue, 0.7), color(hue, 0)] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(halo, startCenter: CGPoint(x: 0, y: 62), startRadius: 0, endCenter: CGPoint(x: 0, y: 62), endRadius: 80, options: [])

            // Glass, tapering toward the socket.
            let glass = CGMutablePath()
            glass.move(to: CGPoint(x: -12, y: 22))
            glass.addCurve(to: CGPoint(x: 0, y: 100), control1: CGPoint(x: -34, y: 50), control2: CGPoint(x: -30, y: 100))
            glass.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 30, y: 100), control2: CGPoint(x: 34, y: 50))
            glass.closeSubpath()
            context.saveGState()
            context.addPath(glass)
            context.clip()
            let lit = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF), color(hue), color(hue)] as CFArray, locations: [0, 0.45, 1])!
            context.drawRadialGradient(lit, startCenter: CGPoint(x: -4, y: 66), startRadius: 0, endCenter: CGPoint(x: 0, y: 64), endRadius: 42, options: [])
            context.restoreGState()

            // Socket.
            context.setFillColor(color(0x1C4A2A))
            context.addPath(CGPath(roundedRect: CGRect(x: -12, y: -4, width: 24, height: 30), cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
    }

    // A gentle highlight along the top edge of the tile.
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.12))
    context.setLineWidth(4)
    context.strokePath()
}

func render(pixels: Int) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / canvas
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    context.interpolationQuality = .high
    drawIcon(in: context)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "SeasonMyMac/Assets.xcassets/AppIcon.appiconset")

// (point size, scale) pairs required for a macOS app icon.
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: points * scale).write(to: iconSet.appending(path: name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appending(path: "Contents.json"))

let docs = root.appending(path: "docs")
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
try render(pixels: 512).write(to: docs.appending(path: "logo.png"))
print("Icon written to \(iconSet.path) and docs/logo.png")
