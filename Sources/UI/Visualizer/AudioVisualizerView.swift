import AppDomain
import SwiftUI

/// The visualizer column: click to cycle visuals; hover for the full-screen button. While
/// Spotify is paused the picture freezes as it was, so it can be studied.
struct AudioVisualizerView: View {
    @ObservedObject var preferences: Preferences
    let visualizer: LiveAudioVisualizer
    let isPlaying: Bool
    /// Spotify's own volume, 0–100.
    let spotifyVolume: Double
    let openFullScreen: () -> Void
    @State private var labelShownAt: Date?
    @State private var isHovering = false

    private static let labelDuration: TimeInterval = 1.4
    private static let labelFadeDuration: TimeInterval = 0.3

    var body: some View {
        LiveVisualizerTimeline(visualizer: visualizer, isPlaying: isPlaying) { frame, date in
            ZStack(alignment: .bottom) {
                VisualizerCanvas(
                    style: preferences.visualizerStyle, frame: frame,
                    surroundings: VisualizerSurroundings(accent: Color(preferences.accentColor), date: date, spotifyVolume: spotifyVolume)
                )
                overlay(now: Date())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            preferences.visualizerStyle = preferences.visualizerStyle.next
            labelShownAt = Date()
        }
        .pointingHandCursor()
        .help("\(preferences.visualizerStyle.label) – click for the next visual")
        .overlay(alignment: .topTrailing) {
            if isHovering { fullScreenButton.transition(.opacity) }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    /// Only shown while hovering, so it never covers a visual's labels otherwise.
    private var fullScreenButton: some View {
        Button(action: openFullScreen) {
            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Full screen: the player and every visual")
        .pointingHandCursor()
    }

    /// Briefly names the visual after a click; explains when there's no sound to show.
    @ViewBuilder
    private func overlay(now: Date) -> some View {
        if let shown = labelShownAt, now.timeIntervalSince(shown) < Self.labelDuration {
            Text(preferences.visualizerStyle.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
                .opacity(min(1, (Self.labelDuration - now.timeIntervalSince(shown)) / Self.labelFadeDuration))
                .padding(.bottom, 8)
        } else if let issue = visualizer.issue(isPlaying: isPlaying, now: now) {
            VisualizerIssueMessage(issue: issue)
                .padding(.bottom, 8)
        }
    }
}
