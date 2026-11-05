import AppDomain
import Foundation

/// Lyrics from LRCLIB (lrclib.net), an open database of synced lyrics.
package struct LRCLIBLyricsProvider: LyricsProvider {
    package let name = "LRCLIB"
    /// LRCLIB asks clients to identify themselves.
    private static let userAgent = "Barsong/1.0 (macOS menu bar app)"
    /// Search results within this many seconds of the track count as the same recording.
    private static let durationTolerance: TimeInterval = 3

    struct Record: Decodable, Equatable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    private let transport: HTTPTransport

    package init(transport: HTTPTransport) {
        self.transport = transport
    }

    package func lyrics(for track: Track) async -> FetchedLyrics? {
        await record(for: track).map { FetchedLyrics(synced: $0.syncedLyrics, plain: $0.plainLyrics) }
    }

    /// The exact match if it has synced lyrics, else the best result of a looser search.
    private func record(for track: Track) async -> Record? {
        if let exact: Record = await transport.fetchJSON(Self.exactMatchURL(for: track), userAgent: Self.userAgent),
           exact.syncedLyrics != nil {
            return exact
        }
        let results: [Record] = await transport.fetchJSON(Self.searchURL(for: track), userAgent: Self.userAgent) ?? []
        return Self.bestSearchResult(results, for: track)
    }

    static func exactMatchURL(for track: Track) -> URL {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        return components.url!
    }

    static func searchURL(for track: Track) -> URL {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
        ]
        return components.url!
    }

    /// Prefers synced results of the same length, then any synced result, then anything.
    static func bestSearchResult(_ results: [Record], for track: Track) -> Record? {
        let synced = results.filter { $0.syncedLyrics?.isEmpty == false }
        return synced.first { abs(($0.duration ?? 0) - track.duration) < durationTolerance }
            ?? synced.first
            ?? results.first
    }
}
