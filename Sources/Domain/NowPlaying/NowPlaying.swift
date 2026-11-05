import Combine
import Foundation

/// What's playing in Spotify right now, plus the playback controls.
@MainActor
package final class NowPlaying: ObservableObject {
    @Published package private(set) var track: Track?
    @Published package private(set) var isPlaying = false
    @Published package private(set) var position = PlaybackPosition(seconds: 0, measuredAt: Date())
    /// Cover of the current track; nil while loading or when there is none.
    @Published package private(set) var artwork: Artwork?
    /// Colours from the latest cover. Kept until the next cover has loaded, so colours fade
    /// from one track to the next instead of flashing grey.
    @Published package private(set) var albumPalette: AlbumPalette?
    @Published package private(set) var isShuffling = false
    @Published package private(set) var isRepeating = false
    /// Spotify's own volume, 0–100 (independent of the system volume).
    @Published package private(set) var volume: Double = 50

    /// Sent after a full re-read of the player (at launch and when the panel opens).
    package let didRefresh = PassthroughSubject<Void, Never>()

    private let player: MusicPlayer
    private let artworkLoader: ArtworkLoader
    private var artworkURL: URL? {
        didSet { if artworkURL != oldValue { loadArtwork() } }
    }

    package init(player: MusicPlayer, artworkLoader: ArtworkLoader) {
        self.player = player
        self.artworkLoader = artworkLoader
        player.onPlaybackChange = { [weak self] snapshot in
            self?.applyPlaybackChange(snapshot)
        }
        refresh()
    }

    package var isPlayerRunning: Bool { player.isRunning }

    /// Current position, extrapolated from the last known one while playing.
    package func currentPosition(at now: Date) -> TimeInterval {
        guard let track else { return 0 }
        return position.extrapolated(to: now, isPlaying: isPlaying, duration: track.duration)
    }

    // MARK: Reading the player

    /// Re-reads the full state. Used at launch and when the panel opens, so the position,
    /// shuffle, repeat and volume stay accurate.
    package func refresh() {
        switch player.readPlayback() {
        case nil:
            return
        case .nothingPlaying:
            clear()
        case let .playing(snapshot):
            track = snapshot.track
            setPosition(snapshot.position)
            isPlaying = snapshot.isPlaying
            artworkURL = snapshot.artworkURL
            if let shuffling = snapshot.isShuffling { isShuffling = shuffling }
            if let repeating = snapshot.isRepeating { isRepeating = repeating }
            if let volume = snapshot.volume { self.volume = volume }
            didRefresh.send()
        }
    }

    /// Re-reads only the position, so timing-sensitive views (lyrics) don't drift.
    package func resyncPosition() {
        guard track != nil, let seconds = player.readPosition() else { return }
        setPosition(seconds)
    }

    private func applyPlaybackChange(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot else {
            clear()
            return
        }
        let trackChanged = snapshot.track.uri != track?.uri
        track = snapshot.track
        isPlaying = snapshot.isPlaying
        setPosition(snapshot.position)
        // Notifications don't include the cover, so ask for it when the track changes.
        if trackChanged || artworkURL == nil {
            artworkURL = nil
            fetchArtworkURL()
        }
    }

    private func clear() {
        track = nil
        isPlaying = false
        artworkURL = nil
        position = PlaybackPosition(seconds: 0, measuredAt: position.measuredAt)
    }

    private func setPosition(_ seconds: TimeInterval) {
        position = PlaybackPosition(seconds: seconds, measuredAt: Date())
    }

    private func fetchArtworkURL() {
        let requestedURI = track?.uri
        guard let url = player.readArtworkURL(), track?.uri == requestedURI else { return }
        artworkURL = url
    }

    private func loadArtwork() {
        guard let url = artworkURL else {
            artwork = nil
            return
        }
        Task {
            let loaded = await artworkLoader.loadArtwork(from: url)
            guard artworkURL == url else { return } // the track changed meanwhile
            artwork = loaded?.artwork
            albumPalette = loaded?.palette
        }
    }

    // MARK: Controls

    package func playPause() { player.playPause() }
    package func skipToNext() { player.skipToNext() }
    package func skipToPrevious() { player.skipToPrevious() }

    package func seek(to seconds: TimeInterval) {
        guard track != nil else { return }
        player.seek(to: seconds)
        setPosition(seconds)
    }

    package func toggleShuffle() {
        let enabled = !isShuffling
        player.setShuffling(enabled)
        isShuffling = enabled
    }

    package func toggleRepeat() {
        let enabled = !isRepeating
        player.setRepeating(enabled)
        isRepeating = enabled
    }

    /// Sends whole steps only, so dragging the slider doesn't flood Spotify with commands.
    package func setVolume(_ newVolume: Double) {
        let rounded = Int(newVolume.rounded())
        guard rounded != Int(volume.rounded()) else { return }
        volume = Double(rounded)
        player.setVolume(rounded)
    }

    // MARK: Opening things in Spotify

    /// The current track, or just the app when nothing is playing.
    package func openCurrentTrack() {
        if let uri = track?.uri {
            player.open(uri: uri)
        } else {
            player.openApp()
        }
    }

    package func open(uri: String) {
        player.open(uri: uri)
    }

    /// Fallback when the exact link isn't known: search Spotify for the name.
    package func search(for text: String) {
        let query = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        player.open(uri: "spotify:search:" + query)
    }
}
