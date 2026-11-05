@testable import AppDomain
import Foundation
import Testing

struct LRCParserTests {
    @Test func parsesTimestampsAndText() {
        let lines = LRCParser.parse("[00:01.50] Hello\n[01:02.25]World")
        #expect(lines == [LyricLine(time: 1.5, text: "Hello"), LyricLine(time: 62.25, text: "World")])
    }

    @Test func repeatsLinesWithSeveralTimestamps() {
        let lines = LRCParser.parse("[00:10.00][00:30.00] Chorus\n[00:20.00] Verse")
        #expect(lines.map(\.time) == [10, 20, 30])
        #expect(lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
    }

    @Test func keepsInstrumentalGapsAndSkipsTags() {
        let lines = LRCParser.parse("[ar: Artist]\n[00:05.00]\n[00:06.00] Words")
        #expect(lines == [LyricLine(time: 5, text: ""), LyricLine(time: 6, text: "Words")])
    }
}

struct LyricsTimelineTests {
    /// Line 2 is an instrumental gap.
    private let timeline = LyricsTimeline(lines: [
        LyricLine(time: 0, text: "one"),
        LyricLine(time: 10, text: "two"),
        LyricLine(time: 20, text: ""),
        LyricLine(time: 30, text: "four"),
        LyricLine(time: 40, text: "five"),
        LyricLine(time: 50, text: "six"),
    ])

    @Test func findsTheLineThatHasStarted() {
        #expect(timeline.lineIndex(at: 9.9) == 0)
        #expect(timeline.lineIndex(at: 10) == 1)
        #expect(timeline.lineIndex(at: 999) == 5)
        #expect(LyricsTimeline(lines: [LyricLine(time: 5, text: "late")]).lineIndex(at: 1) == nil)
    }

    @Test func showsOnlyTheCurrentLineForOne() {
        #expect(timeline.visibleLines(around: 1, count: 1).map(\.text) == ["two"])
        #expect(timeline.visibleLines(around: 2, count: 1).isEmpty) // a gap shows nothing on its own
    }

    @Test func showsTheNextLineForTwo() {
        #expect(timeline.visibleLines(around: 0, count: 2).map(\.text) == ["one", "two"])
    }

    @Test func skipsGapsAroundTheCurrentLine() {
        let lines = timeline.visibleLines(around: 3, count: 3)
        #expect(lines.map(\.text) == ["two", "four", "five"])
        #expect(lines.map(\.isCurrent) == [false, true, false])
    }

    @Test func showsAGapAsANoteWhenThereIsContext() {
        #expect(timeline.visibleLines(around: 2, count: 5).map(\.text) == ["one", "two", "♪", "four", "five"])
    }
}

struct LyricsLookupTests {
    private let track = Track.song("1")

    @Test func takesTheFirstSyncedLyrics() async {
        let lookup = LyricsLookup(providers: [
            FakeLyricsProvider(name: "First", result: FetchedLyrics(synced: nil, plain: "words")),
            FakeLyricsProvider(name: "Second", result: FetchedLyrics(synced: "[00:01.00] synced", plain: nil)),
        ])
        #expect(await lookup.find(for: track) == .synced([LyricLine(time: 1, text: "synced")], source: "Second"))
    }

    @Test func fallsBackToPlainLyrics() async {
        let lookup = LyricsLookup(providers: [
            FakeLyricsProvider(name: "First", result: FetchedLyrics(synced: "", plain: "words")),
            FakeLyricsProvider(name: "Second", result: nil),
        ])
        #expect(await lookup.find(for: track) == .unsynced("words"))
    }

    @Test func syncedLyricsWithoutTimestampsCountAsNotFound() async {
        let lookup = LyricsLookup(providers: [FakeLyricsProvider(name: "First", result: FetchedLyrics(synced: "no timestamps", plain: "words"))])
        #expect(await lookup.find(for: track) == .notFound)
    }

    @Test func reportsNothingFound() async {
        let lookup = LyricsLookup(providers: [FakeLyricsProvider(name: "First", result: nil)])
        #expect(await lookup.find(for: track) == .notFound)
    }
}

@MainActor
struct LyricsSessionTests {
    private let player = FakeMusicPlayer()
    private let storage = InMemorySettingsStorage()

    /// Playing a track starts loading its lyrics in the background; wait for that to finish.
    private func waitForLyrics(_ session: LyricsSession) async {
        for _ in 0..<100 where session.status == .loading {
            await Task.yield()
        }
    }

    private func makeSession(lrc: String?) -> (LyricsSession, NowPlaying, LyricsPreferences) {
        let nowPlaying = NowPlaying(player: player, artworkLoader: NoArtworkLoader())
        let preferences = LyricsPreferences(storage: storage)
        let lookup = LyricsLookup(providers: [FakeLyricsProvider(name: "Test", result: FetchedLyrics(synced: lrc, plain: nil))])
        storage.values["lyricsInMenuBar"] = true
        return (LyricsSession(nowPlaying: nowPlaying, preferences: preferences, lookup: lookup, storage: storage), nowPlaying, preferences)
    }

    @Test func loadsSyncedLyricsForASong() async {
        let (session, _, _) = makeSession(lrc: "[00:01.00] one\n[00:05.00] two")
        await session.load(for: .song("1"))

        #expect(session.status == .synced)
        #expect(session.source == "Test")
        #expect(session.timeline.lines.count == 2)
    }

    @Test func episodesHaveNoLyrics() async {
        let (session, _, _) = makeSession(lrc: "[00:01.00] one")
        await session.load(for: Track(title: "", artist: "", album: "", uri: "spotify:episode:1", duration: 0))

        #expect(session.status == .notASong)
        #expect(session.hasNoLyrics)
    }

    @Test func followsPlaybackWithTheTimingOffset() async {
        let (session, _, preferences) = makeSession(lrc: "[00:01.00] one\n[00:05.00] two")
        player.announce(.playing(.song("1"), at: 4.5))
        await waitForLyrics(session)
        preferences.timingOffset = 0.6

        session.tick(at: Date())

        #expect(session.currentLineIndex == 1)
        #expect(session.visibleLines.map(\.text) == ["two"])
    }

    @Test func turningOffClearsEverything() async {
        let (session, _, _) = makeSession(lrc: "[00:01.00] one")
        await session.load(for: .song("1"))

        session.isEnabled = false

        #expect(session.status == .off)
        #expect(session.timeline.isEmpty)
        #expect(storage.values["lyricsInMenuBar"] as? Bool == false)
    }

    @Test func clickingALineSeeksThere() async {
        let (session, _, _) = makeSession(lrc: "[00:01.00] one\n[00:05.00] two")
        player.announce(.playing(.song("1")))
        await waitForLyrics(session)

        session.seek(toLine: 1)

        #expect(player.commands.last == "seek 5.0")
        #expect(session.currentLineIndex == 1)
    }
}

@MainActor
struct LyricsPreferencesTests {
    @Test func ignoresUnsupportedLineCounts() {
        let storage = InMemorySettingsStorage()
        storage.values["lyricsVisibleLineCount"] = 4
        #expect(LyricsPreferences(storage: storage).visibleLineCount == 1)
    }

    @Test func remembersAndForgetsTheDraggedPosition() {
        let storage = InMemorySettingsStorage()
        let preferences = LyricsPreferences(storage: storage)
        var resets = 0
        let subscription = preferences.positionResetRequests.sink { resets += 1 }

        preferences.windowAnchor = CGPoint(x: 120, y: 900)
        #expect(LyricsPreferences(storage: storage).windowAnchor == CGPoint(x: 120, y: 900))

        preferences.resetPosition()
        #expect(preferences.windowAnchor == nil)
        #expect(resets == 1)
        subscription.cancel()
    }
}
