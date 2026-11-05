import Foundation

/// The music app being shown and controlled (the Spotify desktop app).
@MainActor
package protocol MusicPlayer: AnyObject {
    var isRunning: Bool { get }

    /// Called on every play, pause, skip or seek, with nil when playback stops or the app quits.
    var onPlaybackChange: ((PlaybackSnapshot?) -> Void)? { get set }

    /// Reads the full playback state. Nil when the reply couldn't be understood.
    /// Never launches the app.
    func readPlayback() -> PlayerReading?
    func readArtworkURL() -> URL?
    func readPosition() -> TimeInterval?

    func playPause()
    func skipToNext()
    func skipToPrevious()
    func seek(to seconds: TimeInterval)
    func setShuffling(_ enabled: Bool)
    func setRepeating(_ enabled: Bool)
    /// 0–100.
    func setVolume(_ volume: Int)

    /// Opens a Spotify URI (track, artist, album or search) in the app.
    func open(uri: String)
    func openApp()
}
