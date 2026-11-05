import Foundation

/// An sRGB colour with 8-bit channels, as typed in hex ("1ED760").
package struct SRGBColor: Equatable, Hashable, Sendable {
    package var red: Int
    package var green: Int
    package var blue: Int

    package init(red: Int, green: Int, blue: Int) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    /// Exactly six hex digits, no prefix ("1ED760").
    package init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = Int(hex, radix: 16) else { return nil }
        self.init(red: (value >> 16) & 0xFF, green: (value >> 8) & 0xFF, blue: value & 0xFF)
    }

    /// Lenient parsing of what someone typed: "#ff8800", "FF 88 00". Nil unless six hex digits remain.
    package init?(typed text: String) {
        self.init(hex: String(text.uppercased().filter(\.isHexDigit)))
    }

    /// "1ED760".
    package var hex: String { String(format: "%02X%02X%02X", red, green, blue) }

    package enum Channel: Int, CaseIterable, Sendable { case red, green, blue }

    package subscript(channel: Channel) -> Int {
        get {
            switch channel {
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .red: red = Self.clamped(newValue)
            case .green: green = Self.clamped(newValue)
            case .blue: blue = Self.clamped(newValue)
            }
        }
    }

    package var hsb: HSBColor {
        HSBColor(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    private static func clamped(_ value: Int) -> Int { max(0, min(255, value)) }
}

/// Hue, saturation and brightness, each 0...1.
package struct HSBColor: Equatable, Hashable, Sendable {
    package var hue: Double
    package var saturation: Double
    package var brightness: Double

    package init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    /// From sRGB components, each 0...1.
    package init(red: Double, green: Double, blue: Double) {
        let maxChannel = max(red, green, blue), minChannel = min(red, green, blue)
        let delta = maxChannel - minChannel
        brightness = maxChannel
        saturation = maxChannel == 0 ? 0 : delta / maxChannel
        guard delta > 0 else {
            hue = 0
            return
        }
        let sector: Double
        if maxChannel == red {
            sector = (green - blue) / delta
        } else if maxChannel == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        let wrapped = (sector / 6).truncatingRemainder(dividingBy: 1)
        hue = wrapped < 0 ? wrapped + 1 : wrapped
    }
}
