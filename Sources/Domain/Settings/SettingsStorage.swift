import Foundation

/// Where settings are kept between launches. Values are property-list types
/// (Bool, Int, Double, String).
package protocol SettingsStorage: AnyObject {
    func value<Value>(forKey key: String) -> Value?
    /// Nil removes the value.
    func set<Value>(_ value: Value?, forKey key: String)
}

/// Turning "open at login" on and off.
@MainActor
package protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
