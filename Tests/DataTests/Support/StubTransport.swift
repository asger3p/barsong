@testable import AppData
import AppDomain
import Foundation

/// Answers requests from a list of canned responses, in order, and records what was sent.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Response {
        var status = 200
        var body = ""
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var sent: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response: Response = lock.withLock {
            sent.append(request)
            return responses.isEmpty ? Response(status: 404) : responses.removeFirst()
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        return (Data(response.body.utf8), http)
    }
}

final class InMemorySettingsStorage: SettingsStorage {
    var values: [String: Any] = [:]

    func value<Value>(forKey key: String) -> Value? { values[key] as? Value }

    func set<Value>(_ value: Value?, forKey key: String) {
        values[key] = value
    }
}

final class InMemoryRefreshTokenStore: RefreshTokenStore {
    var token: String?

    func read() -> String? { token }
    func write(_ token: String) { self.token = token }
    func delete() { token = nil }
}

extension URLRequest {
    var queryItems: [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    var formFields: [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(data: httpBody ?? Data(), encoding: .utf8)
        return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }
}
