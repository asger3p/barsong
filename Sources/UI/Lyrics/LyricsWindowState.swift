import SwiftUI

/// Shared between the lyrics window controller and its SwiftUI content.
@MainActor
final class LyricsWindowState: ObservableObject {
    /// The mouse is over the visible lyrics (shows the controls).
    @Published var isHovering = false
    /// Id of the clickable element under the mouse ("line-3", "control-expand", "handle").
    @Published var hoveredID: String?
    /// Frames in window coordinates (SwiftUI global space, top-left origin).
    var contentFrame: CGRect = .zero
    var clickableFrames: [String: CGRect] = [:]
    /// Visible part of the expanded view's scrolling lyrics (lines outside it are hidden).
    var viewportFrame: CGRect = .zero
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onReset: () -> Void = {}

    static let handleID = "handle"

    static func lineID(_ index: Int) -> String { "line-\(index)" }

    static func isLineID(_ id: String) -> Bool { id.hasPrefix("line-") }
}

struct LyricsContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct LyricsViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct LyricsClickableFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// The visible lyrics: the window only takes the mouse inside this frame.
    func reportsLyricsContentFrame() -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: LyricsContentFrameKey.self, value: geometry.frame(in: .global))
        })
    }

    /// Marks a clickable element, so the window can show the pointing hand over it.
    /// (Hover events don't reach a background app's panel; the controller hit-tests these.)
    func lyricsClickable(_ id: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: LyricsClickableFramesKey.self, value: [id: geometry.frame(in: .global)])
        })
    }
}
