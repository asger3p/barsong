import AppDomain
import Foundation

/// Synced lyrics from NetEase Cloud Music, for songs LRCLIB doesn't have
/// (the same fallback LyricFever uses).
package struct NetEaseLyricsProvider: LyricsProvider {
    package let name = "NetEase"
    private static let userAgent = HTTPClientIdentity.userAgent
    private static let durationTolerance: TimeInterval = 3
    /// NetEase's placeholder for instrumentals ("pure music, please enjoy").
    private static let instrumentalMarker = "纯音乐"
    /// Credit lines like "[00:00.00] 作词 : Name" (lyricist, composer, producer).
    private static let creditLine = try! NSRegularExpression(pattern: #"^(\[[\d:.]+\])+\s*[^\s:：]*\p{Han}[^\s:：]*\s*[:：]"#)

    struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            let id: Int
            /// Milliseconds.
            let duration: Double?
            let artists: [Artist]
        }
        struct Artist: Decodable { let name: String }
        let result: Result?
    }

    struct LyricsResponse: Decodable {
        struct Lrc: Decodable { let lyric: String? }
        let lrc: Lrc?
    }

    private let transport: HTTPTransport

    package init(transport: HTTPTransport) {
        self.transport = transport
    }

    package func lyrics(for track: Track) async -> FetchedLyrics? {
        guard let search: SearchResponse = await transport.fetchJSON(Self.searchURL(for: track), userAgent: Self.userAgent),
              let match = Self.matchingSong(in: search.result?.songs ?? [], for: track),
              let response: LyricsResponse = await transport.fetchJSON(Self.lyricsURL(songID: match.id), userAgent: Self.userAgent),
              let lrc = response.lrc?.lyric, !lrc.contains(Self.instrumentalMarker)
        else { return nil }

        let cleaned = Self.removingCreditLines(from: lrc)
        guard LRCParser.parse(cleaned).contains(where: { !$0.text.isEmpty }) else { return nil }
        return FetchedLyrics(synced: cleaned, plain: nil)
    }

    /// "Song - Remastered 2011" and "Song (feat. X)" search as "Song".
    static func searchTitle(for title: String) -> String {
        title.components(separatedBy: " - ").first?.components(separatedBy: " (feat").first ?? title
    }

    static func searchURL(for track: Track) -> URL {
        var components = URLComponents(string: "https://music.163.com/api/search/get")!
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(track.artist) \(searchTitle(for: track.title))"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return components.url!
    }

    static func lyricsURL(songID: Int) -> URL {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
        ]
        return components.url!
    }

    /// A song with the same length (±3 s) and an overlapping artist name.
    static func matchingSong(in songs: [SearchResponse.Song], for track: Track) -> SearchResponse.Song? {
        let artist = track.artist.lowercased()
        return songs.first { song in
            let sameLength = abs((song.duration ?? 0) / 1000 - track.duration) < durationTolerance
            let sameArtist = song.artists.contains {
                let name = $0.name.lowercased()
                return artist.contains(name) || name.contains(artist)
            }
            return sameLength && sameArtist
        }
    }

    static func removingCreditLines(from lrc: String) -> String {
        lrc.components(separatedBy: .newlines).filter { line in
            creditLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) == nil
        }.joined(separator: "\n")
    }
}
