import SwiftUI

/// One place for the visual language, so rows, chooser and empty state agree.
enum Theme {
    /// Matches the rust card on the app icon.
    static let accent = Color(.sRGB, red: 0.85, green: 0.46, blue: 0.34, opacity: 1)
    static let running = Color(.sRGB, red: 0.30, green: 0.78, blue: 0.44, opacity: 1)

    static let popoverWidth: CGFloat = 320
    static let rowHeight: CGFloat = 44
    static let corner: CGFloat = 8

    /// 150-300ms band; skipped entirely when the system asks for less motion.
    static var transition: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.18)
    }
}

/// Hover feedback plus the pointing-hand cursor every clickable row should have.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .onHover { inside in
                withAnimation(Theme.transition) { hovering = inside }
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}
