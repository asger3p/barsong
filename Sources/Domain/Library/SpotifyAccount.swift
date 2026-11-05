import Combine
import Foundation

/// The connection to the user's Spotify account, needed for Liked Songs and artist/album links.
@MainActor
package final class SpotifyAccount: ObservableObject {
    private static let clientIDKey = "spotifyClientID"

    @Published package var clientID: String {
        didSet {
            storage.set(clientID, forKey: Self.clientIDKey)
            authenticator.clientID = clientID
        }
    }
    @Published package private(set) var isConnected: Bool
    /// Waiting for the user to approve access in the browser.
    @Published package private(set) var isConnecting = false
    /// Last problem talking to Spotify, shown in the panel; nil when all is well.
    @Published package var lastError: String?

    /// Sent after a successful sign-in.
    package let didConnect = PassthroughSubject<Void, Never>()

    private let authenticator: AccountAuthenticator
    private let storage: SettingsStorage

    package init(authenticator: AccountAuthenticator, storage: SettingsStorage) {
        self.authenticator = authenticator
        self.storage = storage
        clientID = storage.value(forKey: Self.clientIDKey) ?? ""
        isConnected = authenticator.isConnected
        authenticator.clientID = clientID
        authenticator.onConnectionChange = { [weak self] connected in
            self?.isConnected = connected
        }
    }

    package var redirectURI: String { authenticator.redirectURI }

    /// Spotify Client IDs are 32 hexadecimal characters.
    package static func looksLikeClientID(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy(\.isHexDigit)
    }

    /// Connects as soon as a complete Client ID has been pasted or typed, so there's no
    /// button to press.
    package func connectIfClientIDLooksComplete() async {
        guard Self.looksLikeClientID(clientID), !isConnected, !isConnecting else { return }
        await connect()
    }

    package func connect() async {
        lastError = nil
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            lastError = "Paste your Client ID first."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await authenticator.signIn()
            lastError = nil
            didConnect.send()
        } catch is CancellationError {
            // A newer sign-in took over.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops waiting for the browser.
    package func cancelConnecting() {
        authenticator.cancelSignIn()
    }

    package func disconnect() {
        authenticator.signOut()
    }
}
