import AppKit

// Editable vector geometry, rasterized at each native macOS icon resolution.
let output = CommandLine.arguments[1]
let files = FileManager.default
try files.createDirectory(atPath: output + "/AppIcon.iconset", withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func render(size: Int, destination: String, menu: Bool = false) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.imageInterpolation = .high
    if !menu {
        let plate = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194)
        let shadow = NSShadow()
        shadow.shadowColor = color(0x050A12, alpha: 0.32)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        color(0x121B22).setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [color(0x111820), color(0x25313B)])!.draw(in: plate, angle: 68)
        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        NSGradient(colors: [color(0x57CCBA, alpha: 0.09), color(0x57CCBA, alpha: 0.0)])!
            .draw(fromCenter: NSPoint(x: 700, y: 770), radius: 0,
                  toCenter: NSPoint(x: 700, y: 770), radius: 800, options: [.drawsAfterEndingLocation])
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 192, yRadius: 192)
        edge.lineWidth = 2
        color(0xC9E3E7, alpha: 0.18).setStroke()
        edge.stroke()
    }
    let widths: CGFloat = menu ? 52 : 48
    let bars: [(CGFloat, CGFloat)] = [(278, 112), (358, 224), (438, 344), (518, 224)]
    for (x, height) in bars {
        let path = NSBezierPath(roundedRect: NSRect(x: x, y: 512 - height / 2, width: widths, height: height),
                                xRadius: widths / 2, yRadius: widths / 2)
        if menu { NSColor.black.setFill(); path.fill() }
        else {
            NSGradient(colors: [color(0x9CACB7), color(0xF3F6F7), color(0xDCE5E8)])!.draw(in: path, angle: 85)
        }
    }
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 625, y: 684))
    cursor.line(to: NSPoint(x: 705, y: 684))
    cursor.move(to: NSPoint(x: 665, y: 684))
    cursor.line(to: NSPoint(x: 665, y: 340))
    cursor.move(to: NSPoint(x: 625, y: 340))
    cursor.line(to: NSPoint(x: 705, y: 340))
    cursor.lineWidth = menu ? 40 : 34
    cursor.lineCapStyle = .round
    cursor.lineJoinStyle = .round
    if menu {
        NSColor.black.setStroke()
        cursor.stroke()
    } else {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(0x79E3CD, alpha: 0.22)
        glow.shadowBlurRadius = 18
        glow.shadowOffset = .zero
        glow.set()
        color(0x8DE2CC).setStroke()
        cursor.stroke()
        NSGraphicsContext.restoreGraphicsState()
        color(0xB8F2E3, alpha: 0.65).setStroke()
        cursor.lineWidth = 10
        cursor.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
}

try render(size: 1024, destination: output + "/Voxa-icon.png")
for points in [16, 32, 128, 256, 512] {
    try render(size: points, destination: output + "/AppIcon.iconset/icon_\(points)x\(points).png")
    try render(size: points * 2, destination: output + "/AppIcon.iconset/icon_\(points)x\(points)@2x.png")
}
try render(size: 64, destination: output + "/MenuIcon.png", menu: true)
print("Rendered Voxa icon at all macOS resolutions")
