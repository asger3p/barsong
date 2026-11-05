import AppData
import AppDomain
import AppKit
import AppUI

/// Composition root: builds the data adapters, hands them to the domain models, and
/// gives those to the UI.
@main
@MainActor
final class BarsongApp: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var lyrics: LyricsSession?

    static func main() {
        // `Barsong --enable-launch-at-login` registers the login item and exits,
        // so it can be turned on from the terminal (same as the switch in Settings).
        if CommandLine.arguments.contains("--enable-launch-at-login") {
            do {
                try MainAppLoginItem().setEnabled(true)
                print("Launch at login: enabled")
                exit(0)
            } catch {
                print("Launch at login failed: \(error)")
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = BarsongApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let storage = UserDefaultsSettingsStorage()
        let transport = URLSessionTransport()

        let authenticator = SpotifyAuthenticator(
            transport: transport,
            tokenStore: KeychainRefreshTokenStore(),
            storage: storage,
            openInBrowser: { NSWorkspace.shared.open($0) }
        )
        let library = SpotifyWebAPIClient(transport: transport, tokens: authenticator)
        let account = SpotifyAccount(authenticator: authenticator, storage: storage)
        let nowPlaying = NowPlaying(player: AppleScriptSpotifyPlayer(), artworkLoader: RemoteArtworkLoader(transport: transport))
        let lyricsPreferences = LyricsPreferences(storage: storage)
        let lyrics = LyricsSession(
            nowPlaying: nowPlaying,
            preferences: lyricsPreferences,
            lookup: LyricsLookup(providers: [
                LRCLIBLyricsProvider(transport: transport),
                NetEaseLyricsProvider(transport: transport),
            ]),
            storage: storage
        )
        lyrics.startFollowingPlayback()
        self.lyrics = lyrics

        let trackLinks = CurrentTrackLinks(nowPlaying: nowPlaying, library: library, account: account)
        statusBar = StatusBarController(models: AppModels(
            nowPlaying: nowPlaying,
            likedSongs: LikedSongs(nowPlaying: nowPlaying, library: library, account: account),
            trackLinks: trackLinks,
            account: account,
            lyrics: lyrics,
            lyricsPreferences: lyricsPreferences,
            preferences: Preferences(storage: storage),
            visualizer: LiveAudioVisualizer(source: CoreAudioSpotifyTap()),
            loginItem: MainAppLoginItem()
        ))
    }
}
