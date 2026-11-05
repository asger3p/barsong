@testable import AppData
import AppDomain
import Foundation
import Testing

struct SpotifyPlaybackParsingTests {
    private func reply(_ fields: [String]) -> String {
        fields.joined(separator: SpotifyPlaybackParsing.fieldSeparator)
    }

    @Test func readsTheFullStateReply() {
        let output = reply(["Song", "Artist", "Album", "spotify:track:1", "215000", "12,5", "playing", "https://i.scdn.co/image/1", "true", "false", "65"])
        guard case let .playing(snapshot) = SpotifyPlaybackParsing.playerReading(fromScriptOutput: output) else {
            Issue.record("Expected a playing state")
            return
        }
        #expect(snapshot.track == Track(title: "Song", artist: "Artist", album: "Album", uri: "spotify:track:1", duration: 215))
        #expect(snapshot.position == 12.5) // comma from a European locale
        #expect(snapshot.isPlaying)
        #expect(snapshot.artworkURL?.absoluteString == "https://i.scdn.co/image/1")
        #expect(snapshot.isShuffling == true)
        #expect(snapshot.isRepeating == false)
        #expect(snapshot.volume == 65)
    }

    @Test func anEmptyReplyMeansNothingIsPlaying() {
        #expect(SpotifyPlaybackParsing.playerReading(fromScriptOutput: "") == .nothingPlaying)
    }

    @Test func aShortReplyCantBeRead() {
        #expect(SpotifyPlaybackParsing.playerReading(fromScriptOutput: reply(["Song", "Artist"])) == nil)
    }

    @Test func olderRepliesLeaveShuffleAndVolumeUnknown() {
        let output = reply(["Song", "Artist", "Album", "spotify:track:1", "1000", "0", "paused", ""])
        guard case let .playing(snapshot) = SpotifyPlaybackParsing.playerReading(fromScriptOutput: output) else {
            Issue.record("Expected a playing state")
            return
        }
        #expect(!snapshot.isPlaying)
        #expect(snapshot.isShuffling == nil)
        #expect(snapshot.volume == nil)
    }

    @Test func readsPlaybackNotifications() {
        let snapshot = SpotifyPlaybackParsing.snapshot(fromNotification: [
            "Player State": "Paused", "Track ID": "spotify:track:9", "Name": "Song", "Artist": "Artist",
            "Album": "Album", "Duration": NSNumber(value: 180_000), "Playback Position": NSNumber(value: 30.5),
        ])
        #expect(snapshot?.track.duration == 180)
        #expect(snapshot?.position == 30.5)
        #expect(snapshot?.isPlaying == false)
        #expect(snapshot?.artworkURL == nil)
    }

    @Test func aStoppedNotificationMeansNothingPlays() {
        #expect(SpotifyPlaybackParsing.snapshot(fromNotification: ["Player State": "Stopped", "Track ID": "spotify:track:9"]) == nil)
    }
}

struct PKCETests {
    /// RFC 7636, appendix B.
    @Test func matchesTheSpecificationExample() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomValuesAreURLSafe() {
        let value = PKCE.randomURLSafeString(byteCount: 64)
        #expect(value.count == 86)
        #expect(value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

@MainActor
struct SpotifyAuthenticatorTests {
    private let storage = InMemorySettingsStorage()
    private let tokens = InMemoryRefreshTokenStore()

    private func makeAuthenticator(_ transport: StubTransport, connected: Bool = true) -> SpotifyAuthenticator {
        storage.values["spotifyConnected"] = connected
        let authenticator = SpotifyAuthenticator(transport: transport, tokenStore: tokens, storage: storage, openInBrowser: { _ in })
        authenticator.clientID = "client"
        return authenticator
    }

    @Test func refreshesTheAccessTokenAndKeepsTheNewRefreshToken() async throws {
        tokens.token = "old-refresh"
        let transport = StubTransport([.init(body: #"{"access_token":"access","expires_in":3600,"refresh_token":"new-refresh"}"#)])
        let authenticator = makeAuthenticator(transport)

        #expect(try await authenticator.validAccessToken() == "access")
        #expect(try await authenticator.validAccessToken() == "access") // cached, no second request

        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].formFields == ["grant_type": "refresh_token", "refresh_token": "old-refresh", "client_id": "client"])
        #expect(tokens.token == "new-refresh")
    }

    @Test func aRevokedRefreshTokenSignsOut() async {
        tokens.token = "revoked"
        let authenticator = makeAuthenticator(StubTransport([.init(status: 400, body: "invalid_grant")]))
        var connectionChanges: [Bool] = []
        authenticator.onConnectionChange = { connectionChanges.append($0) }

        await #expect(throws: SpotifyAPIError.http(status: 400, body: "invalid_grant")) {
            try await authenticator.validAccessToken()
        }
        #expect(!authenticator.isConnected)
        #expect(connectionChanges == [false])
        #expect(tokens.token == nil)
        #expect(storage.values["spotifyConnected"] as? Bool == false)
    }

    @Test func needsASessionForTokens() async {
        let authenticator = makeAuthenticator(StubTransport([]), connected: false)
        await #expect(throws: SpotifyAPIError.notConnected) {
            try await authenticator.validAccessToken()
        }
    }

    @Test func asksForLibraryAccessWithPKCE() {
        let authenticator = makeAuthenticator(StubTransport([]))
        let url = authenticator.authorizeURL(challenge: "challenge", state: "state")
        let query = URLRequest(url: url).queryItems
        #expect(url.host == "accounts.spotify.com")
        #expect(query["client_id"] == "client")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == "http://127.0.0.1:43117/callback")
        #expect(query["scope"] == "user-library-read user-library-modify")
    }
}

@MainActor
final class StaticTokenProvider: AccessTokenProvider {
    private(set) var invalidations = 0
    func validAccessToken() async throws -> String { "token-\(invalidations)" }
    func invalidateAccessToken() { invalidations += 1 }
}

@MainActor
struct SpotifyWebAPIClientTests {
    @Test func checksTheLibrary() async throws {
        let transport = StubTransport([.init(body: "[true]")])
        let client = SpotifyWebAPIClient(transport: transport, tokens: StaticTokenProvider())

        #expect(try await client.isSaved("spotify:track:1"))

        let request = transport.requests[0]
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/me/library/contains")
        #expect(request.queryItems["uris"] == "spotify:track:1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-0")
    }

    @Test func savesAndRemoves() async throws {
        let transport = StubTransport([.init(), .init()])
        let client = SpotifyWebAPIClient(transport: transport, tokens: StaticTokenProvider())

        try await client.save("spotify:track:1")
        try await client.remove("spotify:track:1")

        #expect(transport.requests.map(\.httpMethod) == ["PUT", "DELETE"])
        #expect(transport.requests.allSatisfy { $0.url?.path == "/v1/me/library" })
    }

    @Test func readsArtistAndAlbumLinks() async throws {
        let body = #"{"artists":[{"name":"A","uri":"spotify:artist:a"},{"name":"B","uri":"spotify:artist:b"}],"album":{"name":"Album","uri":"spotify:album:1"}}"#
        let transport = StubTransport([.init(body: body)])
        let client = SpotifyWebAPIClient(transport: transport, tokens: StaticTokenProvider())

        let links = try await client.trackLinks(for: "spotify:track:xyz")

        #expect(transport.requests[0].url?.path == "/v1/tracks/xyz")
        #expect(links.artists.map(\.name) == ["A", "B"])
        #expect(links.album == TrackLinks.Link(name: "Album", uri: "spotify:album:1"))
    }

    @Test func retriesOnceWithAFreshTokenAfter401() async throws {
        let transport = StubTransport([.init(status: 401), .init(body: "[false]")])
        let tokens = StaticTokenProvider()
        let client = SpotifyWebAPIClient(transport: transport, tokens: tokens)

        #expect(try await client.isSaved("spotify:track:1") == false)
        #expect(tokens.invalidations == 1)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test func reportsOtherErrors() async {
        let client = SpotifyWebAPIClient(transport: StubTransport([.init(status: 403, body: "Forbidden")]), tokens: StaticTokenProvider())
        await #expect(throws: SpotifyAPIError.http(status: 403, body: "Forbidden")) {
            try await client.save("spotify:track:1")
        }
    }
}

struct OAuthCallbackReceiverTests {
    @Test func readsTheRequestedURL() {
        let components = OAuthCallbackReceiver.requestedURL(in: "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(components?.path == "/callback")
        #expect(components?.queryItems?.first { $0.name == "code" }?.value == "abc")
    }
}

struct SpotifyAPIErrorMessageTests {
    @Test func explainsCommonSetupMistakes() {
        #expect(SpotifyAPIError.http(status: 400, body: #"{"error":"invalid_client"}"#).errorDescription?.contains("doesn't recognise this Client ID") == true)
        #expect(SpotifyAPIError.http(status: 403, body: "").errorDescription?.contains("Web API is ticked") == true)
        #expect(SpotifyAPIError.loginFailed(reason: "access_denied").errorDescription == "Access wasn't approved on Spotify's page.")
        #expect(SpotifyAPIError.http(status: 500, body: "oops").errorDescription == "Spotify API error 500: oops")
    }
}
