// Draws the app icon and writes every size the asset catalog needs.
//
//   swift Tools/make-icon.swift Uproot/Assets.xcassets/AppIcon.appiconset
//
// The mark is a seedling pulled out of the ground, roots and all.

import AppKit

let side: CGFloat = 1024

func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let context = NSGraphicsContext.current?.cgContext else { return image }

    // The rounded square macOS icons sit on, with the usual margin and soft shadow.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    context.addPath(platePath)
    context.setFillColor(NSColor(red: 0.07, green: 0.42, blue: 0.33, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let colors = [
        NSColor(red: 0.20, green: 0.78, blue: 0.58, alpha: 1).cgColor,
        NSColor(red: 0.05, green: 0.47, blue: 0.40, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    // A faint highlight along the top edge.
    if let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1]) {
        context.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    }

    // The hole the plant came out of.
    context.setFillColor(NSColor.black.withAlphaComponent(0.20).cgColor)
    context.fillEllipse(in: CGRect(x: 332, y: 196, width: 360, height: 54))
    context.restoreGState()

    let ink = NSColor.white
    ink.setStroke()
    ink.setFill()

    func stroke(_ width: CGFloat, _ build: (NSBezierPath) -> Void) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        build(path)
        path.stroke()
    }

    // Stem.
    stroke(46) { path in
        path.move(to: NSPoint(x: 512, y: 430))
        path.line(to: NSPoint(x: 512, y: 640))
    }

    // Leaves, one each side of the stem top.
    func leaf(mirrored: Bool) {
        let direction: CGFloat = mirrored ? -1 : 1
        func point(_ dx: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: 512 + direction * dx, y: y) }
        let path = NSBezierPath()
        path.move(to: point(0, 628))
        path.curve(to: point(232, 790), controlPoint1: point(60, 600), controlPoint2: point(220, 640))
        path.curve(to: point(0, 628), controlPoint1: point(120, 812), controlPoint2: point(10, 760))
        path.close()
        path.fill()
    }
    leaf(mirrored: false)
    leaf(mirrored: true)

    // Roots: a tap root and two that spread, each with a side shoot.
    stroke(36) { path in
        path.move(to: NSPoint(x: 512, y: 440))
        path.curve(to: NSPoint(x: 512, y: 262), controlPoint1: NSPoint(x: 512, y: 380), controlPoint2: NSPoint(x: 524, y: 320))
    }
    for direction in [CGFloat(-1), 1] {
        stroke(32) { path in
            path.move(to: NSPoint(x: 512, y: 430))
            path.curve(to: NSPoint(x: 512 + direction * 150, y: 300),
                       controlPoint1: NSPoint(x: 512 + direction * 20, y: 360),
                       controlPoint2: NSPoint(x: 512 + direction * 120, y: 370))
        }
        stroke(24) { path in
            path.move(to: NSPoint(x: 512 + direction * 84, y: 362))
            path.curve(to: NSPoint(x: 512 + direction * 218, y: 372),
                       controlPoint1: NSPoint(x: 512 + direction * 130, y: 372),
                       controlPoint2: NSPoint(x: 512 + direction * 180, y: 392))
        }
    }
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <AppIcon.appiconset>\n".utf8))
    exit(2)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let icon = drawIcon()
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let data = png(icon, pixels: points * scale) else { continue }
        try data.write(to: folder.appendingPathComponent(name))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
print("wrote \(entries.count) images to \(folder.path)")
