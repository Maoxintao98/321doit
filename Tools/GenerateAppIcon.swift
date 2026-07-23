import AppKit
import CoreGraphics
import Foundation

// Renders the 321Doit logo into a macOS iconset folder.
//
// Usage: GenerateAppIcon <iconset-output-dir>
// The directory must already exist; existing PNGs will be overwritten.

guard CommandLine.arguments.count == 2 else {
    fputs("usage: GenerateAppIcon <iconset-dir>\n", stderr)
    exit(2)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Brand palette (must mirror AppLogo.swift)
let inkTop      = NSColor(srgbRed: 0.10, green: 0.13, blue: 0.18, alpha: 1)
let inkBottom   = NSColor(srgbRed: 0.04, green: 0.06, blue: 0.10, alpha: 1)
let accent      = NSColor(srgbRed: 0.30, green: 0.78, blue: 1.00, alpha: 1)
let accentDeep  = NSColor(srgbRed: 0.14, green: 0.50, blue: 0.95, alpha: 1)
let warm        = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.30, alpha: 1)

func renderIcon(size: CGFloat) -> Data? {
    let pixelSize = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pixelSize * 4,
        bitsPerPixel: 32
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setShouldAntialias(true)
    cg.interpolationQuality = .high

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)

    // Inset the actual tile to leave macOS-icon-style breathing room
    let inset = size * 0.085
    let tileRect = canvas.insetBy(dx: inset, dy: inset)
    let radius = tileRect.width * 0.235

    // Background squircle gradient
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
    cg.saveGState()
    tilePath.addClip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [inkTop.cgColor, inkBottom.cgColor] as CFArray,
        locations: [0, 1]
    ) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
            end: CGPoint(x: tileRect.midX, y: tileRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Subtle inner border
    cg.saveGState()
    NSColor.white.withAlphaComponent(0.06).setStroke()
    let borderPath = NSBezierPath(roundedRect: tileRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    borderPath.lineWidth = max(0.5, size * 0.006)
    borderPath.stroke()
    cg.restoreGState()

    // Three stacked bars in 3:2:1 ratio
    let barAreaWidth = tileRect.width * 0.66
    let barHeight = tileRect.width * 0.115
    let barSpacing = tileRect.width * 0.085
    let barRadius = tileRect.width * 0.05

    let totalBarHeight = barHeight * 3 + barSpacing * 2
    let barAreaLeft = tileRect.midX - barAreaWidth / 2
    // Coordinate flip: Cocoa is bottom-up. Top bar (longest) should be visually at top → highest Y.
    let topY = tileRect.midY + totalBarHeight / 2 - barHeight

    let widthRatios: [CGFloat] = [0.62, 0.42, 0.22]
    let topGradients: [(NSColor, NSColor)] = [
        (accent, accentDeep),
        (accent.withAlphaComponent(0.85), accentDeep.withAlphaComponent(0.85)),
        (warm, warm.withAlphaComponent(0.7))
    ]

    for (i, ratio) in widthRatios.enumerated() {
        let y = topY - CGFloat(i) * (barHeight + barSpacing)
        let barRect = CGRect(
            x: barAreaLeft,
            y: y,
            width: barAreaWidth * ratio,
            height: barHeight
        )
        let path = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)
        cg.saveGState()
        path.addClip()
        let (a, b) = topGradients[i]
        if let g = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [a.cgColor, b.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            cg.drawLinearGradient(
                g,
                start: CGPoint(x: barRect.minX, y: barRect.midY),
                end: CGPoint(x: barRect.maxX, y: barRect.midY),
                options: []
            )
        }
        cg.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

struct IconEntry {
    let pixel: Int
    let fileName: String
}

let entries: [IconEntry] = [
    IconEntry(pixel: 16,   fileName: "icon_16x16.png"),
    IconEntry(pixel: 32,   fileName: "icon_16x16@2x.png"),
    IconEntry(pixel: 32,   fileName: "icon_32x32.png"),
    IconEntry(pixel: 64,   fileName: "icon_32x32@2x.png"),
    IconEntry(pixel: 128,  fileName: "icon_128x128.png"),
    IconEntry(pixel: 256,  fileName: "icon_128x128@2x.png"),
    IconEntry(pixel: 256,  fileName: "icon_256x256.png"),
    IconEntry(pixel: 512,  fileName: "icon_256x256@2x.png"),
    IconEntry(pixel: 512,  fileName: "icon_512x512.png"),
    IconEntry(pixel: 1024, fileName: "icon_512x512@2x.png")
]

for entry in entries {
    guard let data = renderIcon(size: CGFloat(entry.pixel)) else {
        fputs("failed to render \(entry.fileName)\n", stderr)
        exit(1)
    }
    let outURL = outDir.appendingPathComponent(entry.fileName)
    try data.write(to: outURL)
}

print("wrote \(entries.count) icons to \(outDir.path)")
