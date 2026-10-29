import AppKit
import JugglerCore

/// Dot images for the menu bar.
///
/// The colored dot is a regular (non-template) image: otherwise the menu bar would recolor it
/// black/white. The gray outline is a template: the system tints it for a light or dark bar.
/// If the frontmost window is a task, its number is drawn inside the dot.
enum MenuBarDotImage {
    /// Image size; the dot itself is slightly smaller.
    static let size = NSSize(width: 18, height: 18)

    static func color(for color: MenuBarDotColor) -> NSColor {
        switch color {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }

    /// Number color on a filled dot: dark on light colors, white on saturated ones.
    static func numberColor(on color: MenuBarDotColor) -> NSColor {
        switch color {
        case .green, .yellow: return NSColor.black.withAlphaComponent(0.8)
        case .orange, .red: return .white
        }
    }

    static func image(for appearance: MenuBarDot.Appearance, number: Int? = nil) -> NSImage {
        switch appearance {
        case .outline:
            let image = NSImage(size: size, flipped: false) { rect in
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.75, dy: 1.75))
                path.lineWidth = 1.5
                NSColor.black.setStroke()
                path.stroke()
                if let number { drawNumber(number, in: rect, color: .black) }
                return true
            }
            image.isTemplate = true
            return image
        case .filled(let dotColor):
            let fill = color(for: dotColor)
            let image = NSImage(size: size, flipped: false) { rect in
                let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                fill.setFill()
                oval.fill()
                // Thin dark rim so yellow and green stay readable on a light bar.
                NSColor.black.withAlphaComponent(0.25).setStroke()
                oval.lineWidth = 0.5
                oval.stroke()
                if let number { drawNumber(number, in: rect, color: numberColor(on: dotColor)) }
                return true
            }
            image.isTemplate = false
            return image
        }
    }

    /// The number centered in the dot; the font shrinks for two and three digits.
    private static func drawNumber(_ number: Int, in rect: NSRect, color: NSColor) {
        let text = String(number)
        let fontSize: CGFloat
        switch text.count {
        case 1: fontSize = 11
        case 2: fontSize = 9
        default: fontSize = 7
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        let origin = NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2)
        string.draw(at: origin)
    }
}
