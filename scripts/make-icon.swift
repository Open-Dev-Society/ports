// Draws the app icon: the panel's treemap on a dark tile.
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
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit) }

    // Apple's icon grid: an 824 tile centred in 1024, leaving room for the shadow.
    let tile = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    color(0x17151F).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x2C2740), ending: color(0x12111A))!.draw(in: tile, angle: -90)

    let tiles: [(NSRect, Int, Int)] = [
        (rect(204, 204, 300, 616), 0x8B6CF0, 0xA48BF5),
        (rect(528, 516, 292, 304), 0x4C9BF0, 0x74B3F5),
        (rect(528, 204, 134, 288), 0x30B0C7, 0x56C6DA),
        (rect(686, 360, 134, 132), 0xE0A030, 0xEAB95F),
    ]
    for (frame, base, light) in tiles {
        NSGradient(starting: color(light), ending: color(base))!
            .draw(in: NSBezierPath(roundedRect: frame, xRadius: 44 * unit, yRadius: 44 * unit), angle: -90)
    }
    let free = NSBezierPath(roundedRect: rect(686, 204, 134, 132), xRadius: 44 * unit, yRadius: 44 * unit)
    NSColor.white.withAlphaComponent(0.14).setFill()
    free.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let folder = "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(pixels: size).write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size).png"))
    try draw(pixels: size * 2).write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)@2x.png"))
}
