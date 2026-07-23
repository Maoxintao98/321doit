import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: GenerateProjectIcon <iconset-dir>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let representations: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, scale: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func drawIcon(pixels: Int) throws -> Data {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    bitmap.size = NSSize(width: side, height: side)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let graphicsContext = context.cgContext
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    // A project is a document package, not another application. Keep the
    // silhouette intentionally simple: a dark production document with one
    // folded corner and the 3:2:1 brand marks.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = side * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.022)
    graphicsContext.saveGState()
    shadow.set()

    let inkTop = NSColor(srgbRed: 0.10, green: 0.13, blue: 0.18, alpha: 1)
    let inkBottom = NSColor(srgbRed: 0.04, green: 0.06, blue: 0.10, alpha: 1)
    let accent = NSColor(srgbRed: 0.30, green: 0.78, blue: 1.00, alpha: 1)
    let accentDeep = NSColor(srgbRed: 0.14, green: 0.50, blue: 0.95, alpha: 1)
    let warm = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.30, alpha: 1)

    let document = NSBezierPath()
    document.move(to: NSPoint(x: side * 0.29, y: side * 0.10))
    document.curve(
        to: NSPoint(x: side * 0.20, y: side * 0.19),
        controlPoint1: NSPoint(x: side * 0.24, y: side * 0.10),
        controlPoint2: NSPoint(x: side * 0.20, y: side * 0.14)
    )
    document.line(to: NSPoint(x: side * 0.20, y: side * 0.77))
    document.curve(
        to: NSPoint(x: side * 0.29, y: side * 0.86),
        controlPoint1: NSPoint(x: side * 0.20, y: side * 0.82),
        controlPoint2: NSPoint(x: side * 0.24, y: side * 0.86)
    )
    document.line(to: NSPoint(x: side * 0.64, y: side * 0.86))
    document.line(to: NSPoint(x: side * 0.82, y: side * 0.68))
    document.line(to: NSPoint(x: side * 0.82, y: side * 0.19))
    document.curve(
        to: NSPoint(x: side * 0.73, y: side * 0.10),
        controlPoint1: NSPoint(x: side * 0.82, y: side * 0.14),
        controlPoint2: NSPoint(x: side * 0.78, y: side * 0.10)
    )
    document.close()

    graphicsContext.saveGState()
    document.addClip()
    NSGradient(colors: [inkTop, inkBottom])?.draw(in: document.bounds, angle: -82)
    graphicsContext.restoreGState()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    document.lineWidth = max(0.8, side * 0.005)
    document.stroke()
    graphicsContext.restoreGState()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: side * 0.64, y: side * 0.86))
    fold.line(to: NSPoint(x: side * 0.64, y: side * 0.73))
    fold.curve(
        to: NSPoint(x: side * 0.70, y: side * 0.67),
        controlPoint1: NSPoint(x: side * 0.64, y: side * 0.695),
        controlPoint2: NSPoint(x: side * 0.665, y: side * 0.67)
    )
    fold.line(to: NSPoint(x: side * 0.82, y: side * 0.67))
    fold.close()
    graphicsContext.saveGState()
    fold.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.35, green: 0.41, blue: 0.50, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.25, blue: 0.33, alpha: 1)
    ])?.draw(in: fold.bounds, angle: -45)
    graphicsContext.restoreGState()
    NSColor.white.withAlphaComponent(0.08).setStroke()
    fold.lineWidth = max(0.8, side * 0.004)
    fold.stroke()

    // Mirror GenerateAppIcon.swift exactly: same 3:2:1 widths and the same
    // cyan-to-blue / cyan-to-blue / gold gradients.
    let barSpecs: [(CGFloat, [NSColor])] = [
        (0.29, [accent, accentDeep]),
        (0.19, [accent.withAlphaComponent(0.85), accentDeep.withAlphaComponent(0.85)]),
        (0.095, [warm, warm.withAlphaComponent(0.70)])
    ]
    for (index, specification) in barSpecs.enumerated() {
        let (width, colors) = specification
        let bar = NSBezierPath(
            roundedRect: rect(0.28, 0.37 - CGFloat(index) * 0.092, width, 0.048, scale: side),
            xRadius: side * 0.024,
            yRadius: side * 0.024
        )
        graphicsContext.saveGState()
        bar.addClip()
        NSGradient(colors: colors)?.draw(in: bar.bounds, angle: 0)
        graphicsContext.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for representation in representations {
    let data = try drawIcon(pixels: representation.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(representation.name), options: .atomic)
}

print("wrote \(representations.count) project icon PNG representations")
