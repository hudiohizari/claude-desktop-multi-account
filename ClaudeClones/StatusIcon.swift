import AppKit

/// The menu bar glyph: three stacked cards, echoing the app icon.
/// Drawn as a template image so macOS tints it for light, dark and highlighted
/// menu bars, and so it stays crisp at any scale factor.
enum StatusIcon {
    static func make(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let unit = rect.width / 18
            let cards: [(y: CGFloat, filled: Bool)] = [(11.5, false), (7.5, false), (3, true)]

            for card in cards {
                let body = NSRect(x: 2.5 * unit, y: card.y * unit,
                                  width: 13 * unit, height: card.filled ? 4.5 * unit : 3 * unit)
                let path = NSBezierPath(roundedRect: body,
                                        xRadius: 1.4 * unit, yRadius: 1.4 * unit)
                if card.filled {
                    NSColor.black.setFill()
                    path.fill()
                } else {
                    NSColor.black.setStroke()
                    path.lineWidth = 1.3 * unit
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude Clones"
        return image
    }
}
