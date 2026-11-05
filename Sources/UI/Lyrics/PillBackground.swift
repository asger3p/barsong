import AppDomain
import SwiftUI

/// Dark: solid black. Light: solid white. Glass: Liquid Glass on macOS 26 (a behind-window
/// blur on older systems). Album: that glass tinted with a gradient from the cover's colours.
struct PillBackground: ViewModifier {
    let style: LyricsPillStyle
    var palette: AlbumPalette?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch style {
        case .album:
            let tint = (palette ?? .black).gradient
            if #available(macOS 26.0, *) {
                content
                    .background(shape.fill(tint).opacity(0.7))
                    .glassEffect(.regular, in: shape)
                    .animation(.easeInOut(duration: 0.8), value: palette)
            } else {
                content
                    .background(ZStack {
                        BehindWindowBlur()
                        shape.fill(tint).opacity(0.7)
                    }.clipShape(shape))
                    .overlay(shape.strokeBorder(.white.opacity(0.15)))
                    .animation(.easeInOut(duration: 0.8), value: palette)
            }
        case .dark:
            content
                .background(shape.fill(.black))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        case .light:
            content
                .background(shape.fill(.white))
                .overlay(shape.strokeBorder(.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        case .glass:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content
                    .background(BehindWindowBlur().clipShape(shape))
                    .overlay(shape.strokeBorder(.white.opacity(0.15)))
            }
        }
    }
}
