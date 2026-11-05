import AppKit
import SwiftUI

/// Shows the pointing hand cursor while hovering, to mark an element as clickable.
///
/// Entering pushes the hand and leaving pops it, so neighbouring elements hand over cleanly.
/// macOS puts the arrow back when you click, and hover events don't fire again while the
/// mouse stays put, so the hand is set again after every click and as the mouse moves.
struct PointingHandCursor: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onContinuousHover { phase in
                if case .active = phase, isHovering { NSCursor.pointingHand.set() }
            }
            .simultaneousGesture(TapGesture().onEnded {
                // After AppKit has handled the click (and reset the cursor).
                DispatchQueue.main.async {
                    if isHovering { NSCursor.pointingHand.set() }
                }
            })
            .onDisappear {
                // Don't leave the hand stuck if the element vanishes under the mouse.
                if isHovering { NSCursor.pop() }
                isHovering = false
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}
