import Combine
import Foundation

/// Whether the current track is in Liked Songs, and adding or removing it.
@MainActor
package final class LikedSongs: ObservableObject {
    /// Nil while unknown: not connected, still checking, or the item can't be saved.
    @Published package private(set) var isCurrentTrackLiked: Bool?

    private let nowPlaying: NowPlaying
    private let library: LibraryRepository
    private let account: SpotifyAccount
    private var cancellables = Set<AnyCancellable>()

    package init(nowPlaying: NowPlaying, library: LibraryRepository, account: SpotifyAccount) {
        self.nowPlaying = nowPlaying
        self.library = library
        self.account = account

        nowPlaying.$track
            .removeDuplicates { $0?.uri == $1?.uri }
            .sink { [weak self] track in
                self?.isCurrentTrackLiked = nil
                Task { await self?.refresh(for: track) }
            }
            .store(in: &cancellables)
        // Liking in Spotify itself shows up the next time the panel opens.
        nowPlaying.didRefresh.merge(with: account.didConnect)
            .sink { [weak self] in Task { await self?.refreshCurrentTrack() } }
            .store(in: &cancellables)
    }

    /// The like button only makes sense for catalogue songs and episodes.
    package var canLikeCurrentTrack: Bool { nowPlaying.track?.canBeSaved == true }

    package func refreshCurrentTrack() async {
        await refresh(for: nowPlaying.track)
    }

    /// Adds the current track to Liked Songs, or removes it. Shows the new state right away
    /// and rolls back if Spotify refuses.
    package func toggleCurrentTrack() async {
        guard let uri = nowPlaying.track?.uri, canLikeCurrentTrack, account.isConnected else { return }
        guard let wasLiked = isCurrentTrackLiked else {
            await refreshCurrentTrack()
            return
        }
        isCurrentTrackLiked = !wasLiked
        do {
            if wasLiked {
                try await library.remove(uri)
            } else {
                try await library.save(uri)
            }
            account.lastError = nil
        } catch {
            if nowPlaying.track?.uri == uri { isCurrentTrackLiked = wasLiked }
            account.lastError = error.localizedDescription
        }
    }

    private func refresh(for track: Track?) async {
        guard let track, track.canBeSaved, account.isConnected else {
            isCurrentTrackLiked = nil
            return
        }
        do {
            let liked = try await library.isSaved(track.uri)
            // Ignore answers for a track that's no longer playing.
            if nowPlaying.track?.uri == track.uri { isCurrentTrackLiked = liked }
        } catch {
            account.lastError = error.localizedDescription
        }
    }
}
