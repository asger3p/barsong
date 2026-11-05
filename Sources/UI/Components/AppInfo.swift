import Foundation

/// The app's name and version, as shown on screen.
enum AppInfo {
    static let name = "Barsong"

    /// "1.0", from the app bundle; empty when running outside one (tests, previews).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
