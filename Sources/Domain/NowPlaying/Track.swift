import Foundation

/// A song, podcast episode, ad or local file playing in Spotify.
package struct Track: Equatable, Sendable {
    package var title: String
    package var artist: String
    package var album: String
    /// Spotify URI: "spotify:track:…", "spotify:episode:…", "spotify:local:…", "spotify:ad:…".
    package var uri: String
    package var duration: TimeInterval

    package init(title: String, artist: String, album: String, uri: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.uri = uri
        self.duration = duration
    }

    /// A song from Spotify's catalogue (not an episode, ad or local file).
    package var isSong: Bool { uri.hasPrefix("spotify:track:") }

    /// Only catalogue songs and podcast episodes can be saved to the library.
    package var canBeSaved: Bool { isSong || uri.hasPrefix("spotify:episode:") }

    /// The open.spotify.com link people can open anywhere ("spotify:track:ID" becomes
    /// "https://open.spotify.com/track/ID"). Nil for local files and ads, which have none.
    package var shareURL: URL? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", ["track", "episode"].contains(parts[1]) else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
}

/// Spotify URIs for a track's artists and album, so they can be opened in Spotify.
package struct TrackLinks: Equatable, Sendable {
    package struct Link: Equatable, Sendable {
        package let name: String
        package let uri: String

        package init(name: String, uri: String) {
            self.name = name
            self.uri = uri
        }
    }

    package let trackURI: String
    package let artists: [Link]
    package let album: Link

    package init(trackURI: String, artists: [Link], album: Link) {
        self.trackURI = trackURI
        self.artists = artists
        self.album = album
    }
}
