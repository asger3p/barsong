import AppDomain
import CoreGraphics

/// Geometry of the menu bar item, shared by the label (which draws it) and the status bar
/// controller (which turns click positions into targets), so click zones line up with the icons.
enum MenuBarLayout {
    enum ClickTarget: Equatable {
        case lyricsIcon, likeIcon, label
    }

    static let trailingIconWidth: CGFloat = 18
    static let itemSpacing: CGFloat = 5

    static func innerPadding(for background: MenuBarBackground) -> CGFloat {
        background == .none ? 6 : 8
    }

    static func outerPadding(for background: MenuBarBackground) -> CGFloat {
        background == .none ? 0 : 3
    }

    /// What a click at `x` hits. `trailingIcons` lists the visible icons from right to left;
    /// each icon's zone reaches halfway into the spacing on either side.
    static func clickTarget(atX x: CGFloat, width: CGFloat, trailingIcons: [ClickTarget], background: MenuBarBackground) -> ClickTarget {
        let trailingInset = innerPadding(for: background) + outerPadding(for: background)
        var zoneStart = width - trailingInset - trailingIconWidth - itemSpacing / 2
        for icon in trailingIcons {
            if x >= zoneStart { return icon }
            zoneStart -= trailingIconWidth + itemSpacing
        }
        return .label
    }
}
