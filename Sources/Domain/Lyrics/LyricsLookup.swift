import Foundation

/// Lyrics as one source has them: LRC with timestamps, plain text, or both.
package struct FetchedLyrics: Equatable, Sendable {
    package var synced: String?
    package var plain: String?

    package init(synced: String?, plain: String?) {
        self.synced = synced
        self.plain = plain
    }
}

/// A lyrics database (LRCLIB, NetEase).
package protocol LyricsProvider: Sendable {
    /// Shown as the source of synced lyrics.
    var name: String { get }
    /// Nil when the source has nothing for the track (or can't be reached).
    func lyrics(for track: Track) async -> FetchedLyrics?
}

package enum LyricsLookupResult: Equatable, Sendable {
    case synced([LyricLine], source: String)
    /// Only words without timestamps were found.
    case unsynced(String)
    case notFound
}

/// Asks each source in turn and takes the first synced lyrics. Plain lyrics are kept as a
/// fallback, from the first source that has them.
package struct LyricsLookup: Sendable {
    private let providers: [LyricsProvider]

    package init(providers: [LyricsProvider]) {
        self.providers = providers
    }

    package func find(for track: Track) async -> LyricsLookupResult {
        var plain: String?
        for provider in providers {
            guard let fetched = await provider.lyrics(for: track) else { continue }
            if let synced = fetched.synced, !synced.isEmpty {
                let lines = LRCParser.parse(synced)
                return lines.isEmpty ? .notFound : .synced(lines, source: provider.name)
            }
            if plain == nil, let text = fetched.plain, !text.isEmpty {
                plain = text
            }
        }
        return plain.map(LyricsLookupResult.unsynced) ?? .notFound
    }
}
