import AppDomain
import SwiftUI

/// Shuffle · previous · play/pause · next · repeat.
struct TransportControls: View {
    @ObservedObject var nowPlaying: NowPlaying
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 18 : 22) {
            ToggleButton(symbol: "shuffle", isOn: nowPlaying.isShuffling, help: "Shuffle", action: nowPlaying.toggleShuffle)
            ControlButton(symbol: "backward.fill", size: isCompact ? 14 : 18, action: nowPlaying.skipToPrevious)
            ControlButton(
                symbol: nowPlaying.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                size: isCompact ? 30 : 40,
                action: nowPlaying.playPause
            )
            ControlButton(symbol: "forward.fill", size: isCompact ? 14 : 18, action: nowPlaying.skipToNext)
            ToggleButton(symbol: "repeat", isOn: nowPlaying.isRepeating, help: "Repeat", action: nowPlaying.toggleRepeat)
        }
    }
}

/// Spotify's own volume (not the system volume).
struct VolumeControl: View {
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            SpotifyStyleBar(value: nowPlaying.volume, range: 0...100, onChanged: nowPlaying.setVolume, onCommit: nowPlaying.setVolume)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The scrubber with elapsed and total time: under the bar in the full player, on either
/// side of it in the compact one (like Spotify's player bar).
struct PlaybackProgress: View {
    @ObservedObject var nowPlaying: NowPlaying
    let track: Track
    let isCompact: Bool
    /// Position under the knob while dragging; nil when not scrubbing.
    @State private var scrubPosition: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = scrubPosition ?? nowPlaying.currentPosition(at: context.date)
            let bar = SpotifyStyleBar(
                value: position,
                range: 0...max(track.duration, 1),
                onChanged: { scrubPosition = $0 },
                // Seek once on release instead of on every drag step.
                onCommit: { target in
                    nowPlaying.seek(to: target)
                    scrubPosition = nil
                }
            )
            Group {
                if isCompact {
                    HStack(spacing: 8) {
                        Text(PlaybackTimeFormat.string(position)).frame(width: 34, alignment: .trailing)
                        bar
                        Text(PlaybackTimeFormat.string(track.duration)).frame(width: 34, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 2) {
                        bar
                        HStack {
                            Text(PlaybackTimeFormat.string(position))
                            Spacer()
                            Text(PlaybackTimeFormat.string(track.duration))
                        }
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
