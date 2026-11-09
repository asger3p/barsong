import AppKit
import SwiftUI

/// Shows the pointing hand cursor while hovering, to mark an element as clickable.
///
/// Entering pushes the hand and leaving pops it, so neighbouring elements hand over cleanly.
/// macOS puts the arrow back when you click, and hover events don't fire again while the
/// mouse stays put, so the hand is set again after every click and as the mouse moves.
struct PointingHandCursor: ViewModifier {
    /// Long enough to swallow a gap between two hover events, short enough to feel instant
    /// when the pointer really has left.
    private static let exitDelay: TimeInterval = 0.05

    @State private var isHovering = false
    /// Bumped by every hover event, so a pending exit knows it has been overtaken.
    @State private var hoverEvents = 0

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering { enter() } else { scheduleExit() }
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

    private func enter() {
        hoverEvents += 1
        guard !isHovering else {
            NSCursor.pointingHand.set()
            return
        }
        isHovering = true
        NSCursor.pointingHand.push()
    }

    /// A button that grows on hover moves its own frame under the pointer, and SwiftUI
    /// reports a moment of "not hovering" before hover resumes. Popping the cursor at once
    /// flashes the arrow, so wait and see whether hover comes back first.
    private func scheduleExit() {
        guard isHovering else { return }
        hoverEvents += 1
        let event = hoverEvents
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitDelay) {
            guard event == hoverEvents, isHovering else { return }
            isHovering = false
            NSCursor.pop()
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}
