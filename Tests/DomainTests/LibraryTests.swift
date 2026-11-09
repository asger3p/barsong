@testable import AppDomain
import Foundation
import Testing

@MainActor
struct LikedSongsTests {
    private let player = FakeMusicPlayer()
    private let library = FakeLibrary()
    private let storage = InMemorySettingsStorage()

    private func makeLikedSongs(connected: Bool = true) -> (LikedSongs, SpotifyAccount) {
        let nowPlaying = NowPlaying(player: player, artworkLoader: NoArtworkLoader())
        player.announce(.playing(.song("1")))
        let account = SpotifyAccount(authenticator: FakeAuthenticator(isConnected: connected), storage: storage)
        return (LikedSongs(nowPlaying: nowPlaying, library: library, account: account), account)
    }

    @Test func checksWhetherTheTrackIsLiked() async {
        library.savedURIs = ["spotify:track:1"]
        let (likedSongs, _) = makeLikedSongs()

        await likedSongs.refreshCurrentTrack()

        #expect(likedSongs.isCurrentTrackLiked == true)
    }

    @Test func staysUnknownWhileNotConnected() async {
        let (likedSongs, _) = makeLikedSongs(connected: false)

        await likedSongs.refreshCurrentTrack()

        #expect(likedSongs.isCurrentTrackLiked == nil)
        #expect(library.calls.isEmpty)
    }

    @Test func showsTheLikeButtonOnlyWhileConnected() {
        let (connected, _) = makeLikedSongs()
        #expect(connected.canLikeCurrentTrack)
        #expect(connected.showsLikeButton)

        let (disconnected, _) = makeLikedSongs(connected: false)
        #expect(disconnected.canLikeCurrentTrack)
        #expect(!disconnected.showsLikeButton)
    }

    @Test func reportsBeingOfflineWithoutCallingItAnError() async {
        let (likedSongs, account) = makeLikedSongs()
        library.failure = URLError(.notConnectedToInternet)

        await likedSongs.refreshCurrentTrack()

        #expect(account.isOffline)
        #expect(account.lastError == nil)
    }

    @Test func stopsSayingOfflineOnceARequestGetsThrough() async {
        let (likedSongs, account) = makeLikedSongs()
        library.failure = URLError(.notConnectedToInternet)
        await likedSongs.refreshCurrentTrack()

        library.failure = nil
        await likedSongs.refreshCurrentTrack()

        #expect(!account.isOffline)
        #expect(account.lastError == nil)
    }

    @Test func stillReportsRealFailures() async {
        let (likedSongs, account) = makeLikedSongs()
        library.failure = TestFailure()

        await likedSongs.refreshCurrentTrack()

        #expect(!account.isOffline)
        #expect(account.lastError == "Something went wrong")
    }

    @Test func likingSavesTheTrack() async {
        let (likedSongs, _) = makeLikedSongs()
        await likedSongs.refreshCurrentTrack()

        await likedSongs.toggleCurrentTrack()

        #expect(likedSongs.isCurrentTrackLiked == true)
        #expect(library.savedURIs == ["spotify:track:1"])
    }

    @Test func unlikingRemovesTheTrack() async {
        library.savedURIs = ["spotify:track:1"]
        let (likedSongs, _) = makeLikedSongs()
        await likedSongs.refreshCurrentTrack()

        await likedSongs.toggleCurrentTrack()

        #expect(likedSongs.isCurrentTrackLiked == false)
        #expect(library.savedURIs.isEmpty)
    }

    @Test func rollsBackAndReportsWhenSpotifyRefuses() async {
        let (likedSongs, account) = makeLikedSongs()
        await likedSongs.refreshCurrentTrack()
        library.failure = TestFailure()

        await likedSongs.toggleCurrentTrack()

        #expect(likedSongs.isCurrentTrackLiked == false)
        #expect(account.lastError == "Something went wrong")
    }

    @Test func togglingBeforeTheStateIsKnownOnlyChecksIt() async {
        let (likedSongs, _) = makeLikedSongs()

        await likedSongs.toggleCurrentTrack()

        #expect(library.calls.allSatisfy { $0.hasPrefix("isSaved") })
        #expect(likedSongs.isCurrentTrackLiked == false)
    }
}

@MainActor
struct SpotifyAccountTests {
    private let storage = InMemorySettingsStorage()

    @Test func needsAClientIDBeforeConnecting() async {
        let account = SpotifyAccount(authenticator: FakeAuthenticator(isConnected: false), storage: storage)
        account.clientID = "   "

        await account.connect()

        #expect(account.lastError == "Paste your Client ID first.")
        #expect(!account.isConnected)
    }

    @Test func connectsAndRemembersTheClientID() async {
        let authenticator = FakeAuthenticator(isConnected: false)
        let account = SpotifyAccount(authenticator: authenticator, storage: storage)
        var connectedEvents = 0
        let subscription = account.didConnect.sink { connectedEvents += 1 }
        account.clientID = " abc123 "

        await account.connect()

        #expect(account.isConnected)
        #expect(connectedEvents == 1)
        #expect(authenticator.clientID == "abc123")
        #expect(storage.values["spotifyClientID"] as? String == "abc123")
        subscription.cancel()
    }

    @Test func showsSignInErrors() async {
        let authenticator = FakeAuthenticator(isConnected: false)
        authenticator.signInError = TestFailure()
        let account = SpotifyAccount(authenticator: authenticator, storage: storage)
        account.clientID = "abc"

        await account.connect()

        #expect(account.lastError == "Something went wrong")
    }

    @Test func followsTheSessionEndingElsewhere() {
        let authenticator = FakeAuthenticator(isConnected: true)
        let account = SpotifyAccount(authenticator: authenticator, storage: storage)

        authenticator.signOut()

        #expect(!account.isConnected)
    }
}

@MainActor
struct CurrentTrackLinksTests {
    @Test func loadsLinksForSongsOnly() async {
        let player = FakeMusicPlayer()
        let library = FakeLibrary()
        let nowPlaying = NowPlaying(player: player, artworkLoader: NoArtworkLoader())
        let account = SpotifyAccount(authenticator: FakeAuthenticator(isConnected: true), storage: InMemorySettingsStorage())
        let trackLinks = CurrentTrackLinks(nowPlaying: nowPlaying, library: library, account: account)
        let episode = Track(title: "", artist: "", album: "", uri: "spotify:episode:9", duration: 0)

        player.announce(.playing(episode))
        await trackLinks.load(for: episode)
        #expect(trackLinks.links == nil)

        player.announce(.playing(.song("1")))
        await trackLinks.load(for: .song("1"))
        #expect(trackLinks.links(for: .song("1"))?.album.name == "Album")
        #expect(trackLinks.links(for: .song("2")) == nil)
    }
}

@MainActor
struct GuidedConnectTests {
    private let validID = "0123456789abcdef0123456789ABCDEF"

    @Test func recognisesClientIDs() {
        #expect(SpotifyAccount.looksLikeClientID(validID))
        #expect(SpotifyAccount.looksLikeClientID("  \(validID)\n"))
        #expect(!SpotifyAccount.looksLikeClientID("0123456789abcdef"))
        #expect(!SpotifyAccount.looksLikeClientID("0123456789abcdef0123456789abcdeg"))
    }

    @Test func connectsOnceAWholeClientIDIsPasted() async {
        let authenticator = FakeAuthenticator(isConnected: false)
        let account = SpotifyAccount(authenticator: authenticator, storage: InMemorySettingsStorage())

        account.clientID = "0123"
        await account.connectIfClientIDLooksComplete()
        #expect(!account.isConnected)

        account.clientID = validID
        await account.connectIfClientIDLooksComplete()
        #expect(account.isConnected)
        #expect(!account.isConnecting)
    }
}
