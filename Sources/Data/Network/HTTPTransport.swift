import Foundation

/// Sends HTTP requests. Swapped for a stub in tests.
package protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

package struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    package init(session: URLSession = .shared) {
        self.session = session
    }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

extension HTTPTransport {
    /// GETs JSON with the given User-Agent. Nil on any failure or a status other than 200.
    func fetchJSON<Value: Decodable>(_ url: URL, userAgent: String) async -> Value? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await send(request), response.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
