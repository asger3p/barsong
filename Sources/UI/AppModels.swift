import AppDomain

/// The domain models the views observe, created by the app's composition root.
@MainActor
package struct AppModels {
    let nowPlaying: NowPlaying
    let likedSongs: LikedSongs
    let trackLinks: CurrentTrackLinks
    let account: SpotifyAccount
    let lyrics: LyricsSession
    let lyricsPreferences: LyricsPreferences
    let preferences: Preferences
    let visualizer: LiveAudioVisualizer
    let loginItem: LoginItem

    package init(
        nowPlaying: NowPlaying,
        likedSongs: LikedSongs,
        trackLinks: CurrentTrackLinks,
        account: SpotifyAccount,
        lyrics: LyricsSession,
        lyricsPreferences: LyricsPreferences,
        preferences: Preferences,
        visualizer: LiveAudioVisualizer,
        loginItem: LoginItem
    ) {
        self.nowPlaying = nowPlaying
        self.likedSongs = likedSongs
        self.trackLinks = trackLinks
        self.account = account
        self.lyrics = lyrics
        self.lyricsPreferences = lyricsPreferences
        self.preferences = preferences
        self.visualizer = visualizer
        self.loginItem = loginItem
    }
}
