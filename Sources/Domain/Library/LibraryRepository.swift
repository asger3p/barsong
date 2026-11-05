import Foundation

/// The signed-in user's Spotify library ("Liked Songs") and track details.
@MainActor
package protocol LibraryRepository: AnyObject {
    func isSaved(_ uri: String) async throws -> Bool
    func save(_ uri: String) async throws
    func remove(_ uri: String) async throws
    func trackLinks(for trackURI: String) async throws -> TrackLinks
}

/// Signs in to a Spotify account (OAuth in the browser) and keeps the session.
@MainActor
package protocol AccountAuthenticator: AnyObject {
    /// Has to be registered in the user's Spotify developer app.
    var redirectURI: String { get }
    /// The user's own Spotify developer app.
    var clientID: String { get set }
    var isConnected: Bool { get }
    /// Called when the session starts or ends (including when Spotify revokes it).
    var onConnectionChange: ((Bool) -> Void)? { get set }

    /// Opens Spotify's login page and waits for the redirect. Throws `CancellationError`
    /// when a newer sign-in replaces this one.
    func signIn() async throws
    /// Gives up on a sign-in waiting for the browser; `signIn()` then throws `CancellationError`.
    func cancelSignIn()
    func signOut()
}
