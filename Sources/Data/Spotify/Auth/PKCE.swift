import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636): lets a public app sign in with only a Client ID.
package enum PKCE {
    /// The S256 challenge sent with the authorize request for a verifier.
    package static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    /// A random verifier or state value.
    package static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    /// Base64 with the URL-safe alphabet and no padding.
    package func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
