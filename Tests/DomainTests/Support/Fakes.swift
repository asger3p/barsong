@testable import AppDomain
import Foundation

final class InMemorySettingsStorage: SettingsStorage {
    var values: [String: Any] = [:]

    func value<Value>(forKey key: String) -> Value? { values[key] as? Value }

    func set<Value>(_ value: Value?, forKey key: String) {
        values[key] = value
    }
}

@MainActor
final class FakeMusicPlayer: MusicPlayer {
    var isRunning = true
    var onPlaybackChange: ((PlaybackSnapshot?) -> Void)?
    var reading: PlayerReading? = .nothingPlaying
    var artworkURL: URL?
    var position: TimeInterval?
    private(set) var commands: [String] = []

    func readPlayback() -> PlayerReading? { reading }
    func readArtworkURL() -> URL? { artworkURL }
    func readPosition() -> TimeInterval? { position }
    func playPause() { commands.append("playPause") }
    func skipToNext() { commands.append("next") }
    func skipToPrevious() { commands.append("previous") }
    func seek(to seconds: TimeInterval) { commands.append("seek \(seconds)") }
    func setShuffling(_ enabled: Bool) { commands.append("shuffle \(enabled)") }
    func setRepeating(_ enabled: Bool) { commands.append("repeat \(enabled)") }
    func setVolume(_ volume: Int) { commands.append("volume \(volume)") }
    func open(uri: String) { commands.append("open \(uri)") }
    func openApp() { commands.append("openApp") }

    /// Simulates Spotify's play/pause/skip notification.
    func announce(_ snapshot: PlaybackSnapshot?) {
        onPlaybackChange?(snapshot)
    }
}

struct NoArtworkLoader: ArtworkLoader {
    func loadArtwork(from url: URL) async -> LoadedArtwork? { nil }
}

@MainActor
final class FakeLibrary: LibraryRepository {
    var savedURIs: Set<String> = []
    var failure: Error?
    private(set) var calls: [String] = []

    func isSaved(_ uri: String) async throws -> Bool {
        calls.append("isSaved \(uri)")
        if let failure { throw failure }
        return savedURIs.contains(uri)
    }

    func save(_ uri: String) async throws {
        calls.append("save \(uri)")
        if let failure { throw failure }
        savedURIs.insert(uri)
    }

    func remove(_ uri: String) async throws {
        calls.append("remove \(uri)")
        if let failure { throw failure }
        savedURIs.remove(uri)
    }

    func trackLinks(for trackURI: String) async throws -> TrackLinks {
        calls.append("links \(trackURI)")
        if let failure { throw failure }
        return TrackLinks(trackURI: trackURI, artists: [.init(name: "Artist", uri: "spotify:artist:1")], album: .init(name: "Album", uri: "spotify:album:1"))
    }
}

@MainActor
final class FakeAuthenticator: AccountAuthenticator {
    let redirectURI = "http://127.0.0.1:1/callback"
    var clientID = ""
    var isConnected: Bool
    var onConnectionChange: ((Bool) -> Void)?
    var signInError: Error?

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    func signIn() async throws {
        if let signInError { throw signInError }
        isConnected = true
        onConnectionChange?(true)
    }

    func cancelSignIn() {}

    func signOut() {
        isConnected = false
        onConnectionChange?(false)
    }
}

struct FakeLyricsProvider: LyricsProvider {
    let name: String
    let result: FetchedLyrics?

    func lyrics(for track: Track) async -> FetchedLyrics? { result }
}

struct TestFailure: LocalizedError {
    var errorDescription: String? { "Something went wrong" }
}

extension Track {
    static func song(_ id: String, title: String = "Song", duration: TimeInterval = 200) -> Track {
        Track(title: title, artist: "Artist", album: "Album", uri: "spotify:track:\(id)", duration: duration)
    }
}

extension PlaybackSnapshot {
    static func playing(_ track: Track, at position: TimeInterval = 0) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, isPlaying: true, position: position)
    }
}
