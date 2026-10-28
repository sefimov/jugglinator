import AppKit
import JugglerCore

/// Картинки кружка для меню-бара.
///
/// Цветной кружок — обычное (не шаблонное) изображение: иначе меню-бар перекрасил бы его
/// в чёрный/белый. Серый контур — шаблонное: система сама красит его под светлый или тёмный бар.
enum MenuBarDotImage {
    /// Размер картинки; сам кружок чуть меньше.
    static let size = NSSize(width: 18, height: 18)

    static func color(for color: MenuBarDotColor) -> NSColor {
        switch color {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }

    static func image(for appearance: MenuBarDot.Appearance) -> NSImage {
        switch appearance {
        case .outline:
            let image = NSImage(size: size, flipped: false) { rect in
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
                path.lineWidth = 1.5
                NSColor.black.setStroke()
                path.stroke()
                return true
            }
            image.isTemplate = true
            return image
        case .filled(let dotColor):
            let fill = color(for: dotColor)
            let image = NSImage(size: size, flipped: false) { rect in
                let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
                fill.setFill()
                oval.fill()
                // Тонкий тёмный ободок, чтобы жёлтый и зелёный читались на светлом баре.
                NSColor.black.withAlphaComponent(0.25).setStroke()
                oval.lineWidth = 0.5
                oval.stroke()
                return true
            }
            image.isTemplate = false
            return image
        }
    }
}
