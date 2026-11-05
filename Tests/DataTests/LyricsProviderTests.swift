@testable import AppData
import AppDomain
import Foundation
import Testing

struct LRCLIBLyricsProviderTests {
    private let track = Track(title: "Song", artist: "Artist", album: "Album", uri: "spotify:track:1", duration: 200.4)

    @Test func usesTheExactMatchWhenItIsSynced() async {
        let transport = StubTransport([.init(body: #"{"syncedLyrics":"[00:01.00] hi","plainLyrics":"hi","duration":200}"#)])
        let lyrics = await LRCLIBLyricsProvider(transport: transport).lyrics(for: track)

        #expect(lyrics == FetchedLyrics(synced: "[00:01.00] hi", plain: "hi"))
        let query = transport.requests[0].queryItems
        #expect(transport.requests[0].url?.path == "/api/get")
        #expect(query == ["artist_name": "Artist", "track_name": "Song", "album_name": "Album", "duration": "200"])
        #expect(transport.requests[0].value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Barsong") == true)
    }

    @Test func searchesWhenThereIsNoExactSyncedMatch() async {
        let search = #"[{"syncedLyrics":null,"plainLyrics":"plain","duration":200},{"syncedLyrics":"[00:01.00] far","duration":260},{"syncedLyrics":"[00:01.00] close","duration":201}]"#
        let transport = StubTransport([.init(status: 404), .init(body: search)])

        let lyrics = await LRCLIBLyricsProvider(transport: transport).lyrics(for: track)

        #expect(transport.requests[1].url?.path == "/api/search")
        #expect(lyrics?.synced == "[00:01.00] close")
    }

    @Test func prefersAnySyncedResultOverPlainOnes() {
        let results = [
            LRCLIBLyricsProvider.Record(syncedLyrics: nil, plainLyrics: "plain", duration: 200),
            LRCLIBLyricsProvider.Record(syncedLyrics: "[00:01.00] synced", plainLyrics: nil, duration: 999),
        ]
        #expect(LRCLIBLyricsProvider.bestSearchResult(results, for: track)?.syncedLyrics == "[00:01.00] synced")
        #expect(LRCLIBLyricsProvider.bestSearchResult([results[0]], for: track)?.plainLyrics == "plain")
        #expect(LRCLIBLyricsProvider.bestSearchResult([], for: track) == nil)
    }
}

struct NetEaseLyricsProviderTests {
    private let track = Track(title: "Song - Remastered 2011", artist: "Artist", album: "Album", uri: "spotify:track:1", duration: 200)

    @Test func searchesWithoutRemasterAndFeatureSuffixes() {
        #expect(NetEaseLyricsProvider.searchTitle(for: "Song - Remastered 2011") == "Song")
        #expect(NetEaseLyricsProvider.searchTitle(for: "Song (feat. Someone)") == "Song")
        #expect(NetEaseLyricsProvider.searchTitle(for: "Song") == "Song")
    }

    @Test func removesCreditLines() {
        let lrc = "[00:00.00] 作词 : Someone\n[00:00.50] 作曲：Someone\n[00:01.00] Real words\n[00:02.00] Words: with a colon"
        #expect(NetEaseLyricsProvider.removingCreditLines(from: lrc) == "[00:01.00] Real words\n[00:02.00] Words: with a colon")
    }

    @Test func fetchesLyricsForTheMatchingSong() async {
        let search = #"{"result":{"songs":[{"id":1,"duration":300000,"artists":[{"name":"Artist"}]},{"id":2,"duration":201000,"artists":[{"name":"artist"}]}]}}"#
        let lyrics = #"{"lrc":{"lyric":"[00:00.00] 作词 : X\n[00:01.00] Hello"}}"#
        let transport = StubTransport([.init(body: search), .init(body: lyrics)])

        let fetched = await NetEaseLyricsProvider(transport: transport).lyrics(for: track)

        #expect(transport.requests[0].queryItems["s"] == "Artist Song")
        #expect(transport.requests[1].queryItems["id"] == "2") // same length and artist
        #expect(fetched == FetchedLyrics(synced: "[00:01.00] Hello", plain: nil))
    }

    @Test func skipsInstrumentals() async {
        let search = #"{"result":{"songs":[{"id":2,"duration":200000,"artists":[{"name":"Artist"}]}]}}"#
        let lyrics = #"{"lrc":{"lyric":"[00:00.00] 纯音乐，请欣赏"}}"#
        let fetched = await NetEaseLyricsProvider(transport: StubTransport([.init(body: search), .init(body: lyrics)])).lyrics(for: track)
        #expect(fetched == nil)
    }

    @Test func needsTheSameArtistAndLength() {
        let songs = [
            NetEaseLyricsProvider.SearchResponse.Song(id: 1, duration: 200_000, artists: [.init(name: "Somebody Else")]),
            NetEaseLyricsProvider.SearchResponse.Song(id: 2, duration: 260_000, artists: [.init(name: "Artist")]),
        ]
        #expect(NetEaseLyricsProvider.matchingSong(in: songs, for: track) == nil)
    }
}

struct UserDefaultsSettingsStorageTests {
    @Test func storesAndRemovesValues() throws {
        let suite = "BarsongTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsSettingsStorage(defaults: defaults)

        storage.set(true, forKey: "flag")
        storage.set(0.5, forKey: "number")
        storage.set("text", forKey: "string")
        #expect(storage.value(forKey: "flag") == true)
        #expect(storage.value(forKey: "number") == 0.5)
        #expect(storage.value(forKey: "string") == "text")
        #expect((storage.value(forKey: "string") as Int?) == nil)

        storage.set(nil as String?, forKey: "string")
        #expect((storage.value(forKey: "string") as String?) == nil)
    }
}
