import AppDomain
import Foundation

/// The user's library through the Spotify Web API (endpoints as of the February 2026 changes).
@MainActor
package final class SpotifyWebAPIClient: LibraryRepository {
    private static let baseURL = "https://api.spotify.com/v1"

    private let transport: HTTPTransport
    private let tokens: AccessTokenProvider

    package init(transport: HTTPTransport, tokens: AccessTokenProvider) {
        self.transport = transport
        self.tokens = tokens
    }

    package func isSaved(_ uri: String) async throws -> Bool {
        let data = try await send("GET", "/me/library/contains", query: ["uris": uri])
        return try JSONDecoder().decode([Bool].self, from: data).first ?? false
    }

    package func save(_ uri: String) async throws {
        _ = try await send("PUT", "/me/library", query: ["uris": uri])
    }

    package func remove(_ uri: String) async throws {
        _ = try await send("DELETE", "/me/library", query: ["uris": uri])
    }

    private struct TrackResponse: Decodable {
        struct Item: Decodable {
            let name: String
            let uri: String
        }
        let artists: [Item]
        let album: Item
    }

    package func trackLinks(for trackURI: String) async throws -> TrackLinks {
        let id = trackURI.replacingOccurrences(of: "spotify:track:", with: "")
        let response = try JSONDecoder().decode(TrackResponse.self, from: try await send("GET", "/tracks/\(id)"))
        return TrackLinks(
            trackURI: trackURI,
            artists: response.artists.map { TrackLinks.Link(name: $0.name, uri: $0.uri) },
            album: TrackLinks.Link(name: response.album.name, uri: response.album.uri)
        )
    }

    /// Sends an authorised request; on 401 renews the token and tries once more.
    private func send(_ method: String, _ path: String, query: [String: String] = [:], isRetry: Bool = false) async throws -> Data {
        var components = URLComponents(string: Self.baseURL + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.validAccessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        if response.statusCode == 401, !isRetry {
            tokens.invalidateAccessToken()
            return try await send(method, path, query: query, isRetry: true)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SpotifyAPIError.http(status: response.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
