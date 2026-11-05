import SwiftUI

/// Spotify-style bar: a plain fill at rest; on hover the fill turns the accent colour, a white knob
/// appears and the cursor becomes a pointing hand. Click or drag anywhere to set the value.
struct SpotifyStyleBar: View {
    @Environment(\.playerAccent) private var accent

    let value: Double
    let range: ClosedRange<Double>
    /// Called continuously while dragging.
    var onChanged: (Double) -> Void
    /// Called once when the click or drag ends.
    var onCommit: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    private let barHeight: CGFloat = 4
    private let knobSize: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = fraction(of: value)
            let isActive = isHovering || isDragging

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(height: barHeight)
                Capsule()
                    .fill(isActive ? accent : Color.primary)
                    .frame(width: max(width * fraction, barHeight), height: barHeight)
                if isActive {
                    Circle()
                        .fill(.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: width * fraction - knobSize / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle()) // the whole row is the hit area, not just the 4 pt line
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChanged(valueAt(x: drag.location.x, width: width))
                    }
                    .onEnded { drag in
                        isDragging = false
                        onCommit(valueAt(x: drag.location.x, width: width))
                    }
            )
        }
        .frame(height: knobSize + 4)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func valueAt(x: CGFloat, width: CGFloat) -> Double {
        let fraction = width > 0 ? min(max(Double(x / width), 0), 1) : 0
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}
