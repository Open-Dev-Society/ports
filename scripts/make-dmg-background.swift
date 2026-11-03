// Draws the disk image window's background: the app icon as a plug on a cable, and a port that holds Applications.
// Positions match scripts/dmg-settings.py. Finder draws the icons and their names on top.
// Run: swift scripts/make-dmg-background.swift && tiffutil -cathidpicheck dmg@1x.png dmg@2x.png -out Resources/dmg-background.tiff && rm dmg@*.png
import AppKit

let size = NSSize(width: 640, height: 400)
let app = NSPoint(x: 190, y: 200)
let folder = NSPoint(x: 470, y: 200)
let pins = [0x8B6CF0, 0x4C9BF0, 0x30B0C7, 0xE0A030]

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func centred(_ words: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (words as NSString).size(withAttributes: attributes).width
    (words as NSString).draw(at: NSPoint(x: (size.width - width) / 2, y: y), withAttributes: attributes)
}

func draw(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    // Flipped, so y runs down like Finder's icon positions.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: NSGraphicsContext(bitmapImageRep: rep)!.cgContext, flipped: true)
    NSAffineTransform(transform: AffineTransform(translationByX: 0, byY: size.height)).concat()
    NSAffineTransform(transform: AffineTransform(scaleByX: 1, byY: -1)).concat()

    NSGradient(starting: color(0x26252D), ending: color(0x131217))!.draw(in: NSRect(origin: .zero, size: size), angle: 90)
    // A faint dot grid, like a circuit board.
    color(0xFFFFFF, 0.05).setFill()
    for x in stride(from: 10, to: size.width, by: 20) {
        for y in stride(from: 10, to: size.height, by: 20) {
            NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
        }
    }

    centred("Plug it in", y: 26, font: .systemFont(ofSize: 24, weight: .semibold), color: .white)
    centred("Drag Ports into the port to install it.", y: 60, font: .systemFont(ofSize: 13), color: color(0xFFFFFF, 0.6))

    // The port, the same shape as the app icon, with Applications inside it.
    let left = folder.x - 115, right = folder.x + 115, top: CGFloat = 104, bottom: CGFloat = 300, radius: CGFloat = 20
    let port = NSBezierPath()
    port.move(to: NSPoint(x: folder.x + 34, y: bottom + 30))
    port.line(to: NSPoint(x: folder.x + 64, y: bottom))
    port.appendArc(from: NSPoint(x: right, y: bottom), to: NSPoint(x: right, y: top), radius: radius)
    port.appendArc(from: NSPoint(x: right, y: top), to: NSPoint(x: left, y: top), radius: radius)
    port.appendArc(from: NSPoint(x: left, y: top), to: NSPoint(x: left, y: bottom), radius: radius)
    port.appendArc(from: NSPoint(x: left, y: bottom), to: NSPoint(x: folder.x - 64, y: bottom), radius: radius)
    port.line(to: NSPoint(x: folder.x - 64, y: bottom))
    port.line(to: NSPoint(x: folder.x - 34, y: bottom + 30))
    port.close()
    color(0xFFFFFF, 0.04).setFill()
    port.fill()
    port.lineWidth = 4
    port.lineJoinStyle = .round
    color(0xFFFFFF, 0.9).setStroke()
    port.stroke()
    for (index, hex) in pins.enumerated() {
        let pin = NSBezierPath()
        let x = folder.x - 45 + CGFloat(index) * 30
        pin.move(to: NSPoint(x: x, y: top + 14))
        pin.line(to: NSPoint(x: x, y: top + 26))
        pin.lineWidth = 4
        pin.lineCapStyle = .round
        color(hex).setStroke()
        pin.stroke()
    }

    // Finder only lets people drag icons, so the app icon is the plug: the cable runs in from the edge
    // and its boot tucks under the icon, which hides the end.
    let cable = NSBezierPath()
    cable.move(to: NSPoint(x: -10, y: 310))
    cable.curve(to: NSPoint(x: app.x - 66, y: app.y), controlPoint1: NSPoint(x: 50, y: 310), controlPoint2: NSPoint(x: 60, y: app.y))
    cable.lineWidth = 9
    cable.lineCapStyle = .round
    color(0xD9D8DE).setStroke()
    cable.stroke()
    let boot = NSBezierPath()
    boot.move(to: NSPoint(x: app.x - 72, y: app.y - 8))
    boot.line(to: NSPoint(x: app.x - 30, y: app.y - 22))
    boot.line(to: NSPoint(x: app.x - 30, y: app.y + 22))
    boot.line(to: NSPoint(x: app.x - 72, y: app.y + 8))
    boot.close()
    color(0xEDECF1).setFill()
    boot.fill()
    for (index, x) in [290.0, 306.0, 322.0].enumerated() {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: x - 3, y: app.y - 7))
        chevron.line(to: NSPoint(x: x + 3, y: app.y))
        chevron.line(to: NSPoint(x: x - 3, y: app.y + 7))
        chevron.lineWidth = 2.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        color(0xFFFFFF, 0.25 + 0.25 * CGFloat(index)).setStroke()
        chevron.stroke()
    }

    // Finder writes the names in black or white to match light or dark mode. Mid grey reads with both.
    color(0x7A7980).setFill()
    for centre in [app, folder] {
        NSBezierPath(roundedRect: NSRect(x: centre.x - 52, y: centre.y + 63, width: 104, height: 22), xRadius: 11, yRadius: 11).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try draw(scale: 1).write(to: URL(fileURLWithPath: "dmg@1x.png"))
try draw(scale: 2).write(to: URL(fileURLWithPath: "dmg@2x.png"))
