@testable import AppDomain
import Foundation
import Testing

struct TrackTests {
    @Test func songsAndEpisodesCanBeSaved() {
        #expect(Track.song("1").canBeSaved)
        #expect(Track(title: "", artist: "", album: "", uri: "spotify:episode:1", duration: 0).canBeSaved)
        #expect(!Track(title: "", artist: "", album: "", uri: "spotify:local:a:b:c:1", duration: 0).canBeSaved)
        #expect(!Track(title: "", artist: "", album: "", uri: "spotify:ad:1", duration: 0).canBeSaved)
    }

    @Test func onlyCatalogueTracksAreSongs() {
        #expect(Track.song("1").isSong)
        #expect(!Track(title: "", artist: "", album: "", uri: "spotify:episode:1", duration: 0).isSong)
    }
}

struct PlaybackPositionTests {
    private let measured = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func advancesWhilePlaying() {
        let position = PlaybackPosition(seconds: 10, measuredAt: measured)
        #expect(position.extrapolated(to: measured.addingTimeInterval(5), isPlaying: true, duration: 200) == 15)
    }

    @Test func standsStillWhilePaused() {
        let position = PlaybackPosition(seconds: 10, measuredAt: measured)
        #expect(position.extrapolated(to: measured.addingTimeInterval(5), isPlaying: false, duration: 200) == 10)
    }

    @Test func neverPassesTheEnd() {
        let position = PlaybackPosition(seconds: 198, measuredAt: measured)
        #expect(position.extrapolated(to: measured.addingTimeInterval(10), isPlaying: true, duration: 200) == 200)
    }
}

@MainActor
struct NowPlayingTests {
    private let player = FakeMusicPlayer()

    private func makeNowPlaying() -> NowPlaying {
        NowPlaying(player: player, artworkLoader: NoArtworkLoader())
    }

    @Test func readsTheFullStateAtLaunch() {
        player.reading = .playing(PlaybackSnapshot(
            track: .song("1"), isPlaying: true, position: 42, isShuffling: true, isRepeating: false, volume: 70
        ))
        let nowPlaying = makeNowPlaying()

        #expect(nowPlaying.track == .song("1"))
        #expect(nowPlaying.isPlaying)
        #expect(nowPlaying.position.seconds == 42)
        #expect(nowPlaying.isShuffling)
        #expect(nowPlaying.volume == 70)
    }

    @Test func followsPlaybackNotifications() {
        let nowPlaying = makeNowPlaying()
        player.announce(.playing(.song("2"), at: 5))

        #expect(nowPlaying.track?.uri == "spotify:track:2")
        #expect(nowPlaying.position.seconds == 5)

        player.announce(nil)
        #expect(nowPlaying.track == nil)
        #expect(!nowPlaying.isPlaying)
    }

    @Test func anUnreadableReplyKeepsTheCurrentState() {
        let nowPlaying = makeNowPlaying()
        player.announce(.playing(.song("1")))
        player.reading = nil

        nowPlaying.refresh()

        #expect(nowPlaying.track == .song("1"))
    }

    @Test func togglesShuffleAndRepeat() {
        let nowPlaying = makeNowPlaying()
        nowPlaying.toggleShuffle()
        nowPlaying.toggleRepeat()

        #expect(nowPlaying.isShuffling)
        #expect(nowPlaying.isRepeating)
        #expect(player.commands == ["shuffle true", "repeat true"])
    }

    @Test func sendsVolumeOnlyInWholeSteps() {
        let nowPlaying = makeNowPlaying()
        nowPlaying.setVolume(60.2)
        nowPlaying.setVolume(60.4)
        nowPlaying.setVolume(61.6)

        #expect(player.commands == ["volume 60", "volume 62"])
        #expect(nowPlaying.volume == 62)
    }

    @Test func seekingWithoutATrackDoesNothing() {
        let nowPlaying = makeNowPlaying()
        nowPlaying.seek(to: 30)
        #expect(player.commands.isEmpty)
    }

    @Test func seekingMovesThePositionRightAway() {
        let nowPlaying = makeNowPlaying()
        player.announce(.playing(.song("1"), at: 5))
        nowPlaying.seek(to: 30)

        #expect(player.commands == ["seek 30.0"])
        #expect(nowPlaying.position.seconds == 30)
    }

    @Test func searchesWithAnEncodedQuery() {
        let nowPlaying = makeNowPlaying()
        nowPlaying.search(for: "Daft Punk")
        #expect(player.commands == ["open spotify:search:Daft%20Punk"])
    }

    @Test func opensTheAppWhenNothingIsPlaying() {
        let nowPlaying = makeNowPlaying()
        nowPlaying.openCurrentTrack()
        #expect(player.commands == ["openApp"])
    }
}

struct ShareURLTests {
    @Test func songsAndEpisodesHaveOpenSpotifyLinks() {
        #expect(Track.song("4uLU6hMCjMI75M1A2tKUQC").shareURL?.absoluteString == "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        let episode = Track(title: "", artist: "", album: "", uri: "spotify:episode:abc", duration: 0)
        #expect(episode.shareURL?.absoluteString == "https://open.spotify.com/episode/abc")
    }

    @Test func localFilesAndAdsHaveNone() {
        #expect(Track(title: "", artist: "", album: "", uri: "spotify:local:Artist:Album:Song:200", duration: 0).shareURL == nil)
        #expect(Track(title: "", artist: "", album: "", uri: "spotify:ad:123", duration: 0).shareURL == nil)
    }
}
