import AppDomain
import AppKit
import SwiftUI

/// Redraws its content up to 60 times a second with the latest audio frame. While Spotify is
/// paused it hands out the frame from the last moment there was sound, and stops the clock,
/// so the picture freezes as it was.
struct LiveVisualizerTimeline<Content: View>: View {
    let visualizer: LiveAudioVisualizer
    let isPlaying: Bool
    @ViewBuilder let content: (_ frame: VisualizerFrame, _ date: Date) -> Content
    @State private var frozenTime = FrozenTime()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let frame = isPlaying ? visualizer.snapshot() : visualizer.lastAudibleSnapshot()
            content(frame, frozenTime.date(for: context.date, isPlaying: isPlaying))
        }
    }
}

/// One visual, drawn from a frame.
struct VisualizerCanvas: View {
    let style: VisualizerStyle
    let frame: VisualizerFrame
    let surroundings: VisualizerSurroundings

    var body: some View {
        Canvas { graphics, size in
            VisualizerRenderer.draw(style, frame: frame, surroundings: surroundings, in: &graphics, size: size)
        }
        .clipped()
    }
}

/// Explains why there's nothing to see (capture failed, or no permission).
struct VisualizerIssueMessage: View {
    let issue: LiveAudioVisualizer.Issue
    private static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!

    var body: some View {
        VStack(spacing: 6) {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if issue == .noSound {
                Button("Open Privacy & Security") {
                    NSWorkspace.shared.open(Self.privacySettingsURL)
                }
                .controlSize(.small)
                .pointingHandCursor()
            }
        }
    }

    private var message: String {
        switch issue {
        case let .captureFailed(reason): reason
        case .noSound: "No sound coming through. Allow “\(AppInfo.name)” under System Audio Recording."
        }
    }
}

/// The moment the picture froze, so anything driven by time stops too.
private final class FrozenTime {
    private var lastPlayingDate = Date()

    func date(for now: Date, isPlaying: Bool) -> Date {
        if isPlaying { lastPlayingDate = now }
        return lastPlayingDate
    }
}
