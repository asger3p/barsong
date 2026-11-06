import AppDomain
import SwiftUI

/// The cover; clicking it opens the track in Spotify.
struct ArtworkView: View {
    @ObservedObject var nowPlaying: NowPlaying
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = ArtworkImages.image(for: nowPlaying.artwork) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").font(.system(size: size * 0.18)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(radius: size > 100 ? 6 : 2, y: size > 100 ? 3 : 1)
        .onTapGesture(perform: nowPlaying.openCurrentTrack)
        .pointingHandCursor()
        .help("Open in Spotify")
    }
}

/// Each artist is its own link, like in Spotify ("Artist A, Artist B"). Without the exact
/// links (not connected), the name searches Spotify instead.
struct ArtistLinks: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var trackLinks: CurrentTrackLinks
    let track: Track

    var body: some View {
        if let artists = trackLinks.links(for: track)?.artists, !artists.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    if index > 0 {
                        Text(", ").foregroundStyle(.secondary)
                    }
                    HoverLink(text: artist.name, style: .secondary) { nowPlaying.open(uri: artist.uri) }
                }
            }
        } else {
            HoverLink(text: track.artist, style: .secondary) { nowPlaying.search(for: track.artist) }
        }
    }
}

/// Title, artists and album under the big cover, with the like button on the right.
struct TrackInfo: View {
    let models: AppModels
    @ObservedObject var trackLinks: CurrentTrackLinks
    @ObservedObject var likedSongs: LikedSongs
    @ObservedObject var account: SpotifyAccount
    let track: Track

    init(models: AppModels, track: Track) {
        self.models = models
        trackLinks = models.trackLinks
        likedSongs = models.likedSongs
        account = models.account
        self.track = track
    }

    var body: some View {
        let nowPlaying = models.nowPlaying
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // Same as clicking the cover: open the song in Spotify.
                HoverLink(text: track.title, style: .primary, lineLimit: 2, action: nowPlaying.openCurrentTrack)
                    .font(.headline)
                ArtistLinks(nowPlaying: nowPlaying, trackLinks: trackLinks, track: track)
                    .font(.subheadline)
                if let album = trackLinks.links(for: track)?.album {
                    HoverLink(text: album.name, style: .tertiary) { nowPlaying.open(uri: album.uri) }
                        .font(.caption)
                } else {
                    HoverLink(text: track.album, style: .tertiary) { nowPlaying.search(for: "\(track.artist) \(track.album)") }
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
            if likedSongs.showsLikeButton {
                LikeButton(likedSongs: likedSongs, size: 22)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
