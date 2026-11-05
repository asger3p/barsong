import SwiftUI

/// Text link styled like Spotify's: dimmed at rest, brighter and underlined on hover.
struct HoverLink: View {
    let text: String
    let style: HierarchicalShapeStyle
    var lineLimit = 1
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(text)
            .underline(isHovering)
            .foregroundStyle(isHovering ? HierarchicalShapeStyle.primary : style)
            .lineLimit(lineLimit)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
            .pointingHandCursor()
    }
}
