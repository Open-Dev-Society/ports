// Draws the app icon: the menu bar's port glyph on a dark tile, its four pins in the panel's colours.
// Run: swift scripts/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = CGFloat(pixels) / 1024

    // Apple's icon grid: an 824 tile centred in 1024, leaving room for the shadow.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit), xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    color(0x1C1B22).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x2E2D36), ending: color(0x141319))!.draw(in: tile, angle: -90)

    // Lucide's "ethernet-port" (ISC licence, lucide.dev) on its 24-point grid, y pointing down.
    // Centred: the outline spans x 2...22 and y 4...20 of the grid.
    let scale = 24 * unit
    let flip = AffineTransform(translationByX: 512 * unit - 12 * scale, byY: 512 * unit + 12 * scale)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { flip.transform(NSPoint(x: x * scale, y: -y * scale)) }

    let outline = NSBezierPath()
    outline.move(to: point(15, 20))
    outline.line(to: point(18, 17))
    outline.appendArc(from: point(22, 17), to: point(22, 4), radius: 2 * scale)
    outline.appendArc(from: point(22, 4), to: point(2, 4), radius: 2 * scale)
    outline.appendArc(from: point(2, 4), to: point(2, 17), radius: 2 * scale)
    outline.appendArc(from: point(2, 17), to: point(6, 17), radius: 2 * scale)
    outline.line(to: point(6, 17))
    outline.line(to: point(9, 20))
    outline.close()
    outline.lineWidth = 1.6 * scale
    outline.lineCapStyle = .round
    outline.lineJoinStyle = .round
    NSColor.white.setStroke()
    outline.stroke()

    for (x, hex) in zip([6, 10, 14, 18], [0x8B6CF0, 0x4C9BF0, 0x30B0C7, 0xE0A030]) {
        let pin = NSBezierPath()
        pin.move(to: point(CGFloat(x), 8))
        pin.line(to: point(CGFloat(x), 10))
        pin.lineWidth = 1.6 * scale
        pin.lineCapStyle = .round
        color(hex).setStroke()
        pin.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let folder = "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(pixels: size).write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size).png"))
    try draw(pixels: size * 2).write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)@2x.png"))
}
