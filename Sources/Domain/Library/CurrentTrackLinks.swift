import Combine
import Foundation

/// Artist and album links for the current track, so they can be opened in Spotify.
@MainActor
package final class CurrentTrackLinks: ObservableObject {
    /// Nil until loaded, or when not connected.
    @Published package private(set) var links: TrackLinks?

    private let nowPlaying: NowPlaying
    private let library: LibraryRepository
    private let account: SpotifyAccount
    private var cancellables = Set<AnyCancellable>()

    package init(nowPlaying: NowPlaying, library: LibraryRepository, account: SpotifyAccount) {
        self.nowPlaying = nowPlaying
        self.library = library
        self.account = account

        nowPlaying.$track
            .sink { [weak self] track in Task { await self?.load(for: track) } }
            .store(in: &cancellables)
        nowPlaying.didRefresh.merge(with: account.didConnect)
            .sink { [weak self] in Task { await self?.load(for: nowPlaying.track) } }
            .store(in: &cancellables)
    }

    /// Links only count when they belong to the track being shown.
    package func links(for track: Track) -> TrackLinks? {
        links?.trackURI == track.uri ? links : nil
    }

    package func load(for track: Track?) async {
        guard let track, track.isSong, account.isConnected else {
            links = nil
            return
        }
        guard links?.trackURI != track.uri else { return }
        guard let loaded = try? await library.trackLinks(for: track.uri),
              nowPlaying.track?.uri == track.uri
        else { return }
        links = loaded
    }
}
