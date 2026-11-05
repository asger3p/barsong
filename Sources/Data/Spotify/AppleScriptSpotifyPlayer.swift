import AppDomain
import AppKit

/// Controls the Spotify desktop app with AppleScript and listens to the playback
/// notifications it broadcasts on every play, pause, skip and seek (so no polling).
@MainActor
package final class AppleScriptSpotifyPlayer: MusicPlayer {
    nonisolated private static let bundleID = "com.spotify.client"
    private static let playbackNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    package var onPlaybackChange: ((PlaybackSnapshot?) -> Void)?

    package init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.playbackNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            MainActor.assumeIsolated {
                self?.onPlaybackChange?(SpotifyPlaybackParsing.snapshot(fromNotification: info))
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.onPlaybackChange?(nil) }
        }
    }

    package var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: Reading

    package func readPlayback() -> PlayerReading? {
        guard isRunning else { return .nothingPlaying }
        guard let output = run(SpotifyScripts.fullState) else { return .nothingPlaying }
        return SpotifyPlaybackParsing.playerReading(fromScriptOutput: output)
    }

    package func readArtworkURL() -> URL? {
        run(SpotifyScripts.artworkURL).flatMap(URL.init(string:))
    }

    package func readPosition() -> TimeInterval? {
        guard isRunning else { return nil }
        return run(SpotifyScripts.position).flatMap(SpotifyPlaybackParsing.optionalNumber)
    }

    // MARK: Controls

    package func playPause() { send("playpause") }
    package func skipToNext() { send("next track") }
    package func skipToPrevious() { send("previous track") }
    package func seek(to seconds: TimeInterval) { send("set player position to \(seconds)") }
    package func setShuffling(_ enabled: Bool) { send("set shuffling to \(enabled)") }
    package func setRepeating(_ enabled: Bool) { send("set repeating to \(enabled)") }
    package func setVolume(_ volume: Int) { send("set sound volume to \(volume)") }

    package func open(uri: String) {
        if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
    }

    package func openApp() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }

    // MARK: AppleScript

    /// Commands are only sent while Spotify runs, so they never launch it.
    private func send(_ command: String) {
        guard isRunning else { return }
        _ = run(SpotifyScripts.command(command))
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Barsong AppleScript error: \(error)") }
        return result?.stringValue
    }
}
