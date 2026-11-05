import Foundation
import Network

/// Tiny HTTP server on 127.0.0.1 that catches Spotify's OAuth redirect.
final class OAuthCallbackReceiver {
    private var listener: NWListener?

    func start(port: UInt16, onCallback: @escaping (URLComponents) -> Void) throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let components = Self.requestedURL(in: request)
                let isCallback = components?.path == "/callback"
                connection.send(content: Self.response(isCallback: isCallback), completion: .contentProcessed { _ in connection.cancel() })
                if isCallback, let components { onCallback(components) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The first line looks like "GET /callback?code=…&state=… HTTP/1.1".
    static func requestedURL(in request: String) -> URLComponents? {
        let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        return URLComponents(string: "http://127.0.0.1" + target)
    }

    private static func response(isCallback: Bool) -> Data {
        let body = isCallback
            ? "<html><body style=\"font-family:-apple-system;padding:40px\"><h2>Done</h2><p>You can close this tab and go back to the menu bar.</p></body></html>"
            : "Not found"
        let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
        return Data(response.utf8)
    }
}
