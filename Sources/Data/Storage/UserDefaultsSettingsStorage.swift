import AppDomain
import Foundation

package final class UserDefaultsSettingsStorage: SettingsStorage {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func value<Value>(forKey key: String) -> Value? {
        defaults.object(forKey: key) as? Value
    }

    package func set<Value>(_ value: Value?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
