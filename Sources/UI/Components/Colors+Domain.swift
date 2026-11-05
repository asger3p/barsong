import AppDomain
import SwiftUI

extension Color {
    init(_ color: SRGBColor) {
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }

    init(_ color: HSBColor) {
        self.init(hue: color.hue, saturation: color.saturation, brightness: color.brightness)
    }
}

extension AlbumPalette {
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(primary), Color(secondary)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Stand-in while no cover has loaded yet.
    static let black = AlbumPalette(
        primary: HSBColor(hue: 0, saturation: 0, brightness: 0),
        secondary: HSBColor(hue: 0, saturation: 0, brightness: 0)
    )
}

/// The app's accent colour (Spotify green by default), passed down to every view that uses it.
private struct PlayerAccentKey: EnvironmentKey {
    static let defaultValue = Color(Preferences.defaultAccent)
}

extension EnvironmentValues {
    var playerAccent: Color {
        get { self[PlayerAccentKey.self] }
        set { self[PlayerAccentKey.self] = newValue }
    }
}
