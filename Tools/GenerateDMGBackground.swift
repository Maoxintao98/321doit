import AppKit
import CoreGraphics
import Foundation

// Deterministic Retina DMG artwork. Finder icon coordinates in package.sh are
// intentionally mirrored here so text and artwork can never drift apart.

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: GenerateDMGBackground <output.png> [width] [height]\n", stderr)
    exit(2)
}

let output = arguments[1]
let logicalWidth = arguments.count > 2 ? (Int(arguments[2]) ?? 760) : 760
let logicalHeight = arguments.count > 3 ? (Int(arguments[3]) ?? 500) : 500
let scale = 2

let canvas = NSSize(width: logicalWidth, height: logicalHeight)
let pixelWidth = logicalWidth * scale
let pixelHeight = logicalHeight * scale

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: pixelWidth * 4,
    bitsPerPixel: 32
) else {
    fatalError("Could not allocate background bitmap")
}
bitmap.size = canvas

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.setShouldAntialias(true)
context.interpolationQuality = .high

let width = CGFloat(logicalWidth)
let height = CGFloat(logicalHeight)
let top = NSColor(srgbRed: 0.055, green: 0.078, blue: 0.118, alpha: 1)
let bottom = NSColor(srgbRed: 0.020, green: 0.030, blue: 0.052, alpha: 1)
let blue = NSColor(srgbRed: 0.11, green: 0.58, blue: 1.00, alpha: 1)
let cyan = NSColor(srgbRed: 0.28, green: 0.80, blue: 1.00, alpha: 1)
let green = NSColor(srgbRed: 0.22, green: 0.76, blue: 0.45, alpha: 1)
let amber = NSColor(srgbRed: 1.00, green: 0.71, blue: 0.25, alpha: 1)

func rounded(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func text(
    _ value: String,
    x: CGFloat,
    y: CGFloat,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center,
    tracking: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    if tracking != 0 { attributes[.kern] = tracking }
    let string = NSAttributedString(string: value, attributes: attributes)
    let size = string.size()
    let originX: CGFloat
    switch alignment {
    case .left: originX = x
    case .right: originX = x - size.width
    default: originX = x - size.width / 2
    }
    string.draw(at: CGPoint(x: originX, y: y - size.height / 2))
}

func pill(_ value: String, centerX: CGFloat, centerY: CGFloat, tint: NSColor) {
    let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    let measured = NSAttributedString(string: value, attributes: [.font: font]).size()
    let rect = CGRect(x: centerX - measured.width / 2 - 13, y: centerY - 12,
                      width: measured.width + 26, height: 24)
    tint.withAlphaComponent(0.12).setFill()
    rounded(rect, radius: 12).fill()
    tint.withAlphaComponent(0.42).setStroke()
    let outline = rounded(rect.insetBy(dx: 0.5, dy: 0.5), radius: 11.5)
    outline.lineWidth = 1
    outline.stroke()
    text(value, x: centerX, y: centerY, font: font,
         color: NSColor.white.withAlphaComponent(0.82), tracking: 0.25)
}

// Deep blue-black background.
if let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [top.cgColor, bottom.cgColor] as CFArray,
    locations: [0, 1]
) {
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height),
                               end: CGPoint(x: width, y: 0), options: [])
}

// Soft brand glow, kept away from Finder labels.
context.saveGState()
context.setShadow(offset: .zero, blur: 70, color: blue.withAlphaComponent(0.34).cgColor)
blue.withAlphaComponent(0.09).setFill()
context.fillEllipse(in: CGRect(x: width / 2 - 105, y: height / 2 - 80, width: 210, height: 210))
context.restoreGState()

// Fine production grid.
NSColor.white.withAlphaComponent(0.022).setFill()
stride(from: CGFloat(18), to: width, by: 18).forEach { x in
    stride(from: CGFloat(18), to: height, by: 18).forEach { y in
        context.fillEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
    }
}

// Header.
let markRect = CGRect(x: 28, y: height - 57, width: 34, height: 34)
NSColor(srgbRed: 0.06, green: 0.09, blue: 0.14, alpha: 0.96).setFill()
rounded(markRect, radius: 9).fill()
NSColor.white.withAlphaComponent(0.10).setStroke()
rounded(markRect.insetBy(dx: 0.5, dy: 0.5), radius: 8.5).stroke()
for (index, pair) in [(cyan, CGFloat(20)), (blue, CGFloat(14)), (amber, CGFloat(8))].enumerated() {
    let y = markRect.maxY - 10 - CGFloat(index) * 8
    pair.0.setFill()
    rounded(CGRect(x: markRect.minX + 7, y: y, width: pair.1, height: 5), radius: 2.5).fill()
}
text("321Doit", x: 74, y: height - 35,
     font: .systemFont(ofSize: 20, weight: .semibold),
     color: NSColor.white.withAlphaComponent(0.94), alignment: .left)
text("OFFLINE INSTALLER  ·  UNIVERSAL 2", x: width - 28, y: height - 35,
     font: .monospacedSystemFont(ofSize: 9, weight: .semibold),
     color: NSColor.white.withAlphaComponent(0.42), alignment: .right, tracking: 1.1)

NSColor.white.withAlphaComponent(0.07).setStroke()
let divider = NSBezierPath()
divider.move(to: CGPoint(x: 28, y: height - 74))
divider.line(to: CGPoint(x: width - 28, y: height - 74))
divider.lineWidth = 0.5
divider.stroke()

// Installer headline and dependency summary.
text("一次安装，直接开工", x: width / 2, y: height - 106,
     font: .systemFont(ofSize: 22, weight: .bold),
     color: NSColor.white.withAlphaComponent(0.95))
text("One install. Ready for set.", x: width / 2, y: height - 132,
     font: .monospacedSystemFont(ofSize: 10, weight: .medium),
     color: NSColor.white.withAlphaComponent(0.48), tracking: 0.8)
pill("321Doit.app", centerX: width / 2 - 122, centerY: height - 164, tint: blue)
pill("FFmpeg", centerX: width / 2, centerY: height - 164, tint: green)
pill("FFprobe", centerX: width / 2 + 112, centerY: height - 164, tint: amber)

// Finder places the package icon at top-down (380, 285). This card sits behind it.
let targetCenter = CGPoint(x: width / 2, y: height - 285)
let targetRect = CGRect(x: targetCenter.x - 91, y: targetCenter.y - 78, width: 182, height: 156)
NSColor.white.withAlphaComponent(0.045).setFill()
rounded(targetRect, radius: 24).fill()
blue.withAlphaComponent(0.55).setStroke()
let targetOutline = rounded(targetRect.insetBy(dx: 0.5, dy: 0.5), radius: 23.5)
targetOutline.lineWidth = 1
targetOutline.setLineDash([5, 5], count: 2, phase: 0)
targetOutline.stroke()

// Bottom instruction stays below Finder's package label.
text("双击「安装 321Doit」", x: width / 2, y: 74,
     font: .systemFont(ofSize: 16, weight: .semibold),
     color: NSColor.white.withAlphaComponent(0.92))
text("安装器会保留电脑上已有依赖；缺少时使用包内离线组件", x: width / 2, y: 50,
     font: .systemFont(ofSize: 10.5, weight: .regular),
     color: NSColor.white.withAlphaComponent(0.55))
text("No Homebrew · No network download · Apple Silicon + Intel", x: width / 2, y: 29,
     font: .monospacedSystemFont(ofSize: 9, weight: .medium),
     color: NSColor.white.withAlphaComponent(0.35), tracking: 0.3)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode background PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(logicalWidth)x\(logicalHeight) @2x DMG background to \(output)")
