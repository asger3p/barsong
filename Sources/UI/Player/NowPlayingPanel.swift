import AppDomain
import SwiftUI

/// The panel under the menu bar item: the player, full or compact, with the visualizer
/// column beside the full one.
struct NowPlayingPanel: View {
    let models: AppModels
    let openSettings: () -> Void
    let openFullScreen: () -> Void
    @ObservedObject private var nowPlaying: NowPlaying
    @ObservedObject private var preferences: Preferences

    init(models: AppModels, openSettings: @escaping () -> Void, openFullScreen: @escaping () -> Void) {
        self.models = models
        self.openSettings = openSettings
        self.openFullScreen = openFullScreen
        nowPlaying = models.nowPlaying
        preferences = models.preferences
    }

    var body: some View {
        playerPage
            .padding(isShowingCompactPlayer ? 12 : 16)
            // The compact bar and the player + visualizer size themselves; everything else is a fixed-width column.
            .frame(width: isShowingCompactPlayer || isShowingVisualizer ? nil : Self.columnWidth)
            .environment(\.playerAccent, Color(preferences.accentColor))
    }

    private static let columnWidth: CGFloat = 300
    private static let visualizerWidth: CGFloat = 268
    private static let visualizerGap: CGFloat = 16

    private var isShowingVisualizer: Bool {
        preferences.showVisualizer && !preferences.compactPlayer && nowPlaying.track != nil
    }

    private var isShowingCompactPlayer: Bool {
        preferences.compactPlayer && nowPlaying.track != nil
    }

    /// The full player, with the visualizer column to its right (behind a divider) when on.
    /// The visualizer sits in an overlay so it takes exactly the player's height.
    @ViewBuilder
    private var playerPage: some View {
        if isShowingVisualizer {
            let width = Self.visualizerWidth, gap = Self.visualizerGap
            playerColumn(showsCornerButtons: false)
                .frame(width: width)
                .padding(.trailing, width + gap * 2 + 1)
                .overlay(alignment: .trailing) {
                    HStack(spacing: gap) {
                        Divider()
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                VisualizerStepper(preferences: preferences)
                                Spacer(minLength: 8)
                                PanelCornerButtons(preferences: preferences, openSettings: openSettings)
                            }
                            AudioVisualizerView(
                                preferences: preferences, visualizer: models.visualizer, isPlaying: nowPlaying.isPlaying,
                                spotifyVolume: nowPlaying.volume, openFullScreen: openFullScreen
                            )
                        }
                        .frame(width: width)
                    }
                }
        } else {
            playerColumn(showsCornerButtons: true)
        }
    }

    private func playerColumn(showsCornerButtons: Bool) -> some View {
        VStack(spacing: 14) {
            if !isShowingCompactPlayer && showsCornerButtons {
                cornerButtons
            }
            if let track = nowPlaying.track {
                if preferences.compactPlayer {
                    CompactPlayer(models: models, track: track, openSettings: openSettings)
                } else {
                    FullPlayer(models: models, track: track)
                }
            } else {
                emptyState
            }
            AccountErrorText(account: models.account)
        }
    }

    /// Settings and quit in the top-right corner.
    private var cornerButtons: some View {
        HStack(spacing: 14) {
            Spacer()
            PanelCornerButtons(preferences: preferences, openSettings: openSettings)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(.secondary)
            Text(nowPlaying.isPlayerRunning ? "Nothing playing" : "Spotify isn't running")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// Big cover, track info, controls over the progress bar, then visualizer/lyrics toggles and
/// volume in the bottom-right corner, like Spotify.
struct FullPlayer: View {
    let models: AppModels
    let track: Track

    var body: some View {
        ArtworkView(nowPlaying: models.nowPlaying, size: 268, cornerRadius: 10)
        TrackInfo(models: models, track: track)
        TransportControls(nowPlaying: models.nowPlaying, isCompact: false)
        PlaybackProgress(nowPlaying: models.nowPlaying, track: track, isCompact: false)
        HStack(spacing: 12) {
            Spacer()
            if let url = track.shareURL {
                ShareLinkButton(url: url)
            }
            VisualizerToggle(preferences: models.preferences)
            LyricsToggle(lyrics: models.lyrics)
            VolumeControl(nowPlaying: models.nowPlaying).frame(width: 130)
        }
    }
}

/// One row, like Spotify's desktop player bar:
/// cover · song/artist · like · controls over progress · settings/quit over lyrics/volume.
struct CompactPlayer: View {
    let models: AppModels
    @ObservedObject var likedSongs: LikedSongs
    @ObservedObject var account: SpotifyAccount
    let track: Track
    let openSettings: () -> Void

    init(models: AppModels, track: Track, openSettings: @escaping () -> Void) {
        self.models = models
        likedSongs = models.likedSongs
        account = models.account
        self.track = track
        self.openSettings = openSettings
    }

    var body: some View {
        let nowPlaying = models.nowPlaying
        HStack(spacing: 16) {
            ArtworkView(nowPlaying: nowPlaying, size: 56, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 2) {
                HoverLink(text: track.title, style: .primary, action: nowPlaying.openCurrentTrack)
                    .font(.callout.weight(.semibold))
                ArtistLinks(nowPlaying: nowPlaying, trackLinks: models.trackLinks, track: track)
                    .font(.caption)
            }
            .frame(width: 150, alignment: .leading)
            if likedSongs.canLikeCurrentTrack && account.isConnected {
                LikeButton(likedSongs: likedSongs, size: 18)
            }
            VStack(spacing: 4) {
                TransportControls(nowPlaying: nowPlaying, isCompact: true)
                PlaybackProgress(nowPlaying: nowPlaying, track: track, isCompact: true)
            }
            .frame(width: 300)
            // Right end: settings/quit in the top corner, lyrics and volume in the bottom corner.
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 14) { PanelCornerButtons(preferences: models.preferences, openSettings: openSettings) }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    if let url = track.shareURL {
                        ShareLinkButton(url: url)
                    }
                    LyricsToggle(lyrics: models.lyrics)
                    VolumeControl(nowPlaying: nowPlaying).frame(width: 110)
                }
            }
            .frame(height: 56)
        }
    }
}

/// The last problem talking to Spotify, if any.
struct AccountErrorText: View {
    @ObservedObject var account: SpotifyAccount

    var body: some View {
        if let error = account.lastError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
