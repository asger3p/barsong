import Foundation

/// What the player reports about the current playback.
package struct PlaybackSnapshot: Equatable, Sendable {
    package var track: Track
    package var isPlaying: Bool
    package var position: TimeInterval
    /// Only known from a full read; play/pause/skip notifications leave these nil.
    package var artworkURL: URL?
    package var isShuffling: Bool?
    package var isRepeating: Bool?
    /// 0–100.
    package var volume: Double?

    package init(
        track: Track,
        isPlaying: Bool,
        position: TimeInterval,
        artworkURL: URL? = nil,
        isShuffling: Bool? = nil,
        isRepeating: Bool? = nil,
        volume: Double? = nil
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.position = position
        self.artworkURL = artworkURL
        self.isShuffling = isShuffling
        self.isRepeating = isRepeating
        self.volume = volume
    }
}

/// Result of reading the player's full state.
package enum PlayerReading: Equatable, Sendable {
    case nothingPlaying
    case playing(PlaybackSnapshot)
}

/// A playback position and when it was measured, so it can be extrapolated while playing.
package struct PlaybackPosition: Equatable, Sendable {
    package var seconds: TimeInterval
    package var measuredAt: Date

    package init(seconds: TimeInterval, measuredAt: Date) {
        self.seconds = seconds
        self.measuredAt = measuredAt
    }

    /// The position at `now`: the last measurement plus the time since while playing,
    /// never past the end of the track.
    package func extrapolated(to now: Date, isPlaying: Bool, duration: TimeInterval) -> TimeInterval {
        let elapsed = isPlaying ? now.timeIntervalSince(measuredAt) : 0
        return min(seconds + elapsed, duration)
    }
}
