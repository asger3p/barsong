import Foundation
import Security

/// Where the long-lived refresh token is kept.
package protocol RefreshTokenStore: AnyObject {
    func read() -> String?
    func write(_ token: String)
    func delete()
}

/// Keeps the refresh token in the login Keychain.
package final class KeychainRefreshTokenStore: RefreshTokenStore {
    private let service: String
    private let account: String

    package init(service: String = "dev.asger.Barsong", account: String = "spotifyRefreshToken") {
        self.service = service
        self.account = account
    }

    package func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    package func write(_ token: String) {
        delete()
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    package func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
