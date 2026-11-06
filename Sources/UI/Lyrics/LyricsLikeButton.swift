import AppDomain
import SwiftUI

/// Adds the current song to Liked Songs from the expanded lyrics view, in the same style as
/// the window controls beside it. Hidden when there is nothing to like, or no Spotify account
/// to like it with.
///
/// The pointing hand and the hover highlight come from the window controller hit-testing
/// `lyricsClickable` frames: a background app's panel doesn't get hover events of its own.
struct LyricsLikeButton: View {
    @ObservedObject var likedSongs: LikedSongs
    /// Observed so the button appears and disappears with the connection.
    @ObservedObject var account: SpotifyAccount
    @ObservedObject var state: LyricsWindowState
    let textColor: Color
    let size: CGFloat

    private static let id = "control-like"

    var body: some View {
        if likedSongs.showsLikeButton {
            let isLiked = likedSongs.isCurrentTrackLiked == true
            Button {
                Task { await likedSongs.toggleCurrentTrack() }
            } label: {
                Image(systemName: isLiked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(textColor.opacity(isLiked || state.hoveredID == Self.id ? 1 : 0.6))
                    .frame(width: size + 8, height: size + 8)
                    .contentShape(Rectangle())
                    .lyricsClickable(Self.id)
            }
            .buttonStyle(.plain)
            .help(isLiked ? "Remove from Liked Songs" : "Add to Liked Songs")
        }
    }
}
