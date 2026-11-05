import AppDomain
import Foundation

package enum SpotifyAPIError: LocalizedError, Equatable {
    case notConnected
    case http(status: Int, body: String)
    case couldNotListen(port: UInt16, reason: String)
    case loginFailed(reason: String?)

    package var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to your Spotify account."
        case let .http(status, body) where status == 400 && body.contains("invalid_client"):
            "Spotify doesn't recognise this Client ID. Copy it again from your app on the Spotify dashboard."
        case let .http(status, _) where status == 403:
            "Spotify refused access. Check that Web API is ticked for your app, and that your Spotify account owns the app (or is added under User Management)."
        case let .http(status, _) where status == 429:
            "Spotify is limiting requests right now. Try again in a minute."
        case let .http(status, body):
            "Spotify API error \(status): \(body.prefix(200))"
        case let .couldNotListen(port, reason):
            "Couldn't listen on port \(port): \(reason)"
        case .loginFailed(reason: "access_denied"):
            "Access wasn't approved on Spotify's page."
        case let .loginFailed(reason):
            "Spotify login failed" + (reason.map { ": \($0)" } ?? ".")
        }
    }
}

/// Hands out a valid access token for Web API calls.
@MainActor
package protocol AccessTokenProvider: AnyObject {
    func validAccessToken() async throws -> String
    /// Forgets the current access token, e.g. after Spotify rejected it.
    func invalidateAccessToken()
}

/// Signs in with the Authorization Code + PKCE flow, so only a Client ID is needed (no
/// secret). Spotify redirects to a tiny server on 127.0.0.1; the refresh token is kept in
/// the Keychain and access tokens are renewed as they expire.
@MainActor
package final class SpotifyAuthenticator: AccountAuthenticator, AccessTokenProvider {
    package static let redirectPort: UInt16 = 43117
    package let redirectURI = "http://127.0.0.1:43117/callback"
    private static let scopes = "user-library-read user-library-modify"
    private static let connectedKey = "spotifyConnected"
    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    /// Renew access tokens this long before they expire.
    private static let expiryMargin: TimeInterval = 60

    package var clientID = ""
    package private(set) var isConnected: Bool
    package var onConnectionChange: ((Bool) -> Void)?

    private let transport: HTTPTransport
    private let tokenStore: RefreshTokenStore
    private let storage: SettingsStorage
    private let openInBrowser: (URL) -> Void
    private let callbackReceiver = OAuthCallbackReceiver()
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private var pendingAuthorization: CheckedContinuation<String, Error>?

    package init(
        transport: HTTPTransport,
        tokenStore: RefreshTokenStore,
        storage: SettingsStorage,
        openInBrowser: @escaping (URL) -> Void
    ) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.storage = storage
        self.openInBrowser = openInBrowser
        isConnected = storage.value(forKey: Self.connectedKey) ?? false
    }

    // MARK: Signing in and out

    package func signIn() async throws {
        let verifier = PKCE.randomURLSafeString(byteCount: 64)
        let code = try await authorizationCode(verifier: verifier)
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        setConnected(true)
    }

    package func cancelSignIn() {
        callbackReceiver.stop()
        pendingAuthorization?.resume(throwing: CancellationError())
        pendingAuthorization = nil
    }

    package func signOut() {
        tokenStore.delete()
        accessToken = nil
        accessTokenExpiry = .distantPast
        setConnected(false)
    }

    /// Opens Spotify's login page and waits for it to redirect back with a code.
    private func authorizationCode(verifier: String) async throws -> String {
        pendingAuthorization?.resume(throwing: CancellationError())
        pendingAuthorization = nil

        let state = PKCE.randomURLSafeString(byteCount: 16)
        do {
            try callbackReceiver.start(port: Self.redirectPort) { [weak self] components in
                MainActor.assumeIsolated { self?.handleCallback(components, expectedState: state) }
            }
        } catch {
            throw SpotifyAPIError.couldNotListen(port: Self.redirectPort, reason: error.localizedDescription)
        }
        let url = authorizeURL(challenge: PKCE.challenge(for: verifier), state: state)
        return try await withCheckedThrowingContinuation { continuation in
            pendingAuthorization = continuation
            openInBrowser(url)
        }
    }

    package func authorizeURL(challenge: String, state: String) -> URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    private func handleCallback(_ components: URLComponents, expectedState: String) {
        callbackReceiver.stop()
        guard let continuation = pendingAuthorization else { return }
        pendingAuthorization = nil
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if value("state") == expectedState, let code = value("code") {
            continuation.resume(returning: code)
        } else {
            continuation.resume(throwing: SpotifyAPIError.loginFailed(reason: value("error")))
        }
    }

    // MARK: Tokens

    package func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(Self.expiryMargin) {
            return accessToken
        }
        guard isConnected, let refreshToken = tokenStore.read() else { throw SpotifyAPIError.notConnected }
        do {
            try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ])
        } catch let SpotifyAPIError.http(status, body) where status == 400 {
            // Refresh token revoked or expired: a fresh login is needed.
            signOut()
            throw SpotifyAPIError.http(status: status, body: body)
        }
        return accessToken ?? ""
    }

    package func invalidateAccessToken() {
        accessToken = nil
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw SpotifyAPIError.http(status: response.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(token.expiresIn)
        // Spotify may rotate the refresh token; always keep the newest one.
        if let refreshToken = token.refreshToken { tokenStore.write(refreshToken) }
    }

    private func setConnected(_ connected: Bool) {
        isConnected = connected
        storage.set(connected, forKey: Self.connectedKey)
        onConnectionChange?(connected)
    }
}
