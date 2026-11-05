import AppDomain
import SwiftUI

/// "+" to add the current track to Liked Songs; a filled check when it's already there.
struct LikeButton: View {
    @ObservedObject var likedSongs: LikedSongs
    @Environment(\.playerAccent) private var accent
    let size: CGFloat

    var body: some View {
        let isLiked = likedSongs.isCurrentTrackLiked == true
        Button {
            Task { await likedSongs.toggleCurrentTrack() }
        } label: {
            Image(systemName: isLiked ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: size))
                .foregroundStyle(isLiked ? accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(isLiked ? "Remove from Liked Songs" : "Add to Liked Songs")
        .pointingHandCursor()
    }
}
