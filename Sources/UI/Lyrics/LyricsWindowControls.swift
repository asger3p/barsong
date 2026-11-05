import AppDomain
import SwiftUI

/// Top-right controls: move handle · reset position · expand/collapse · dismiss.
struct LyricsWindowControls: View {
    @ObservedObject var lyrics: LyricsSession
    @ObservedObject var preferences: LyricsPreferences
    @ObservedObject var state: LyricsWindowState
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.7) {
            // Drag handle: not a button, just a drag target.
            icon("arrow.up.and.down.and.arrow.left.and.right", id: LyricsWindowState.handleID)
                .help("Drag to move")
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in state.onDragChanged() }
                        .onEnded { _ in state.onDragEnded() }
                )
            button("arrow.counterclockwise", id: "control-reset", help: "Reset position (\(preferences.defaultPosition.label.lowercased()))") {
                state.onReset()
            }
            button(preferences.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                   id: "control-expand",
                   help: preferences.isExpanded ? "Collapse" : "Expand") {
                preferences.isExpanded.toggle()
            }
            button("xmark", id: "control-dismiss", help: "Hide lyrics") {
                lyrics.isEnabled = false
            }
        }
    }

    private func icon(_ symbol: String, id: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(preferences.pillStyle.textColor.opacity(state.hoveredID == id ? 1 : 0.6))
            .frame(width: size + 8, height: size + 8)
            .contentShape(Rectangle())
            .lyricsClickable(id)
    }

    private func button(_ symbol: String, id: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol, id: id) }
            .buttonStyle(.plain)
            .help(help)
    }
}
