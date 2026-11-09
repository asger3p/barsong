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
    /// Never holds a connectivity failure: that is `isOffline`.
    @Published package var lastError: String?
    /// Spotify couldn't be reached. Not a fault to report in red — Spotify plays offline
    /// too, and Liked Songs and the links catch up once the network is back.
    @Published package private(set) var isOffline = false

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

    /// A request got through: whatever went wrong before no longer holds.
    package func noteReachable() {
        lastError = nil
        isOffline = false
    }

    /// A request failed. Connectivity failures become `isOffline`; anything else is shown.
    package func note(_ error: Error) {
        if Self.isConnectivityFailure(error) {
            isOffline = true
            lastError = nil
        } else {
            isOffline = false
            lastError = error.localizedDescription
        }
    }

    /// The network is unreachable, rather than Spotify refusing something.
    static func isConnectivityFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            return true
        default:
            return false
        }
    }

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
        noteReachable()
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            lastError = "Paste your Client ID first."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await authenticator.signIn()
            noteReachable()
            didConnect.send()
        } catch is CancellationError {
            // A newer sign-in took over.
        } catch {
            note(error)
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
