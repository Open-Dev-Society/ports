import AppKit
import PortsCore

enum Palette {
    private static let bars = [0x8B6CF0, 0x2F7FE0, 0x30B0C7, 0xE0A030]
    private static let tiles = [0x8B6CF0, 0x4C9BF0, 0x30B0C7, 0xE0A030]

    static func bar(_ index: Int) -> NSColor { color(bars[index % bars.count]) }
    static func tile(_ index: Int) -> NSColor { color(tiles[index % tiles.count]) }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// Drawn text in a custom view skips the popover's vibrancy, where the system's secondary colours nearly vanish.
let dimText = NSColor.labelColor.withAlphaComponent(0.72)
let faintText = NSColor.labelColor.withAlphaComponent(0.5)

/// Diagonal lines for memory that's free.
func drawHatch(in rect: NSRect) {
    let path = NSBezierPath()
    var x = rect.minX - rect.height
    while x < rect.maxX {
        path.move(to: NSPoint(x: x + rect.height, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        x += 9
    }
    NSColor.labelColor.withAlphaComponent(0.28).setStroke()
    path.lineWidth = 1
    path.stroke()
}

/// The budget bar: one coloured part per project, hatching for what's free, marks at 80% and 95%.
final class MeterView: NSView {
    private let segments: [(share: Double, color: NSColor)]
    private let budgetShare: Double

    init(segments: [(Double, NSColor)], budgetShare: Double) {
        self.segments = segments.map { (share: $0.0, color: $0.1) }
        self.budgetShare = budgetShare
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bar = NSRect(x: 0, y: 3, width: bounds.width, height: 10)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).addClip()
        var x: CGFloat = 0
        for segment in segments where segment.share > 0 {
            let width = max(bar.width * segment.share, 2)
            segment.color.setFill()
            NSRect(x: x, y: bar.minY, width: width, height: bar.height).fill()
            x += width + 2
        }
        if x < bar.maxX { drawHatch(in: NSRect(x: x, y: bar.minY, width: bar.maxX - x, height: bar.height)) }
        NSGraphicsContext.restoreGraphicsState()

        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: faintText,
        ]
        for mark in [0.8, 0.95] {
            let markX = (bounds.width * mark * budgetShare).rounded()
            dimText.setFill()
            NSRect(x: markX, y: 0, width: 1, height: 16).fill()
            // Far over budget the marks crowd together, so only the higher one keeps its label.
            if mark == 0.8, bounds.width * 0.15 * budgetShare < 26 { continue }
            let words = "\(Int(mark * 100))%" as NSString
            let width = words.size(withAttributes: label).width
            words.draw(at: NSPoint(x: min(markX - width / 2, bounds.width - width), y: 17), withAttributes: label)
        }
    }
}

/// A treemap tile. It's a real button, so it works with the keyboard and VoiceOver.
final class TileButton: NSButton {
    enum Style { case solid, dashed, free }

    var items: [MapItem] = []
    private let style: Style
    private let primary: String
    private let value: String
    private let tint: NSColor
    private let moon: Bool
    let chosen: Bool

    init(frame: NSRect, style: Style, title: String, value: String, color: NSColor, moon: Bool, selected: Bool, target: AnyObject?, action: Selector?, id: String) {
        self.style = style
        self.primary = title
        self.value = value
        self.tint = color
        self.moon = moon
        self.chosen = selected
        super.init(frame: frame)
        self.title = ""
        isBordered = false
        self.target = target
        self.action = action
        if style != .solid { isEnabled = false }
        if style == .free { setAccessibilityLabel(value) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let edge = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: edge, xRadius: 10, yRadius: 10)
        switch style {
        case .solid:
            // Darkened so white text stays readable on every colour in the palette.
            let solid = chosen ? tint.blended(withFraction: 0.3, of: .black) ?? tint : tint
            solid.withAlphaComponent(chosen ? 1 : isHighlighted ? 0.6 : 0.45).setFill()
            shape.fill()
            solid.setStroke()
        case .dashed:
            shape.setLineDash([4, 3], count: 2, phase: 0)
            tint.setStroke()
        case .free:
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            drawHatch(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        }
        shape.lineWidth = 1
        shape.stroke()

        let faded = style == .dashed
        let inner = bounds.insetBy(dx: 9, dy: 7)
        var y = inner.minY
        if !primary.isEmpty {
            let attributes = textAttributes(.systemFont(ofSize: 12, weight: .medium), chosen ? .white : faded ? dimText : .labelColor)
            (primary as NSString).draw(with: NSRect(x: inner.minX, y: y, width: inner.width - (moon ? 16 : 0), height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            y += 16
        }
        let attributes = textAttributes(.monospacedSystemFont(ofSize: 10.5, weight: .regular), chosen ? .white : faded ? faintText : dimText)
        (value as NSString).draw(with: NSRect(x: inner.minX, y: y, width: inner.width, height: 14), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)

        if moon, let image = NSImage(systemSymbolName: "moon", accessibilityDescription: "Idle")?
            .withSymbolConfiguration(.init(paletteColors: [chosen ? .white : .labelColor])) {
            image.draw(in: NSRect(x: bounds.maxX - 20, y: 8, width: 12, height: 12), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func textAttributes(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }
}

final class StatusPill: NSView {
    private let status: BudgetStatus

    init(status: BudgetStatus) {
        self.status = status
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        widthAnchor.constraint(equalToConstant: 21 + textSize.width.rounded(.up) + 9).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(status.title)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
    }
    private var textSize: NSSize { (status.title as NSString).size(withAttributes: attributes) }
    private var dot: NSColor {
        switch status {
        case .roomToSpare: return .systemGreen
        case .gettingFull: return .systemYellow
        case .almostFull: return .systemOrange
        case .overBudget: return .systemRed
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11).fill()
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: 9, y: 8, width: 6, height: 6)).fill()
        (status.title as NSString).draw(at: NSPoint(x: 21, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
    }
}

final class Swatch: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 10).isActive = true
        heightAnchor.constraint(equalToConstant: 10).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
    }
}
