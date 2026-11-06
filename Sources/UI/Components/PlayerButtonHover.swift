import SwiftUI

/// How the player's buttons answer the pointer, the way Spotify's do: the icon brightens and
/// grows a touch while it's under the mouse. One place, so every button in the player and the
/// panel feels the same.
///
/// Pair it with `pointingHandCursor()`, which marks the button as clickable.
struct PlayerButtonHover: ViewModifier {
    static let scale: CGFloat = 1.15
    static let animation = Animation.easeOut(duration: 0.12)

    /// The icon's colour at rest and while hovered. Nil leaves the icon's own colour alone,
    /// for an icon that's already at full brightness.
    let colors: (resting: Color, hovered: Color)?
    @State private var isHovering = false

    func body(content: Content) -> some View {
        tinted(content)
            .scaleEffect(isHovering ? Self.scale : 1)
            .animation(Self.animation, value: isHovering)
            .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private func tinted(_ content: Content) -> some View {
        if let colors {
            content.foregroundStyle(isHovering ? colors.hovered : colors.resting)
        } else {
            content
        }
    }
}

extension View {
    /// Brightens from `resting` to `hovered` and grows a touch while hovered. Pass the colour
    /// the icon already has at rest; it replaces the button's own `foregroundStyle`.
    ///
    /// An icon with a state colour of its own (an accent for "on" or "liked") passes that same
    /// colour as both, so hovering it only grows.
    func playerButtonHover(from resting: Color, to hovered: Color = .primary) -> some View {
        modifier(PlayerButtonHover(colors: (resting, hovered)))
    }

    /// Grows a touch while hovered, leaving the icon's colour as it is. Only for an icon
    /// that carries its own colour in every state; anything else wants the brightening above,
    /// because 15% on a glyph is a couple of pixels and easy to miss on its own.
    func playerButtonHover() -> some View {
        modifier(PlayerButtonHover(colors: nil))
    }
}
