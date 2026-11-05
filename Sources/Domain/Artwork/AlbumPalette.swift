import Foundation

/// Two colours picked from the album art, darkened enough for white text on top.
package struct AlbumPalette: Equatable, Sendable {
    package let primary: HSBColor
    package let secondary: HSBColor

    package init(primary: HSBColor, secondary: HSBColor) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Side of the square thumbnail the palette is picked from.
    package static let sampleSide = 32

    private static let levelsPerChannel = 6
    private static let minimumDistinctness = 0.35
    private static let primaryMaxBrightness = 0.55
    private static let secondaryMaxBrightness = 0.4

    /// Buckets the pixels by colour (favouring colourful ones over greys) and returns the most
    /// common colour plus the most common clearly different one.
    /// - Parameter pixels: RGBA bytes, 4 per pixel (alpha ignored), usually a 32×32 thumbnail.
    package static func extract(fromRGBA pixels: [UInt8]) -> AlbumPalette? {
        typealias RGB = (red: Double, green: Double, blue: Double)
        struct Bucket { var weight = 0.0, red = 0.0, green = 0.0, blue = 0.0 }

        let steps = Double(levelsPerChannel - 1)
        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: pixels.count - 3, by: 4) {
            let red = Double(pixels[offset]) / 255, green = Double(pixels[offset + 1]) / 255, blue = Double(pixels[offset + 2]) / 255
            let maxChannel = max(red, green, blue), minChannel = min(red, green, blue)
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
            let weight = 0.15 + saturation * maxChannel // colourful, not-too-dark pixels count most
            let key = (Int(red * steps) * levelsPerChannel + Int(green * steps)) * levelsPerChannel + Int(blue * steps)
            buckets[key, default: Bucket()].weight += weight
            buckets[key, default: Bucket()].red += red * weight
            buckets[key, default: Bucket()].green += green * weight
            buckets[key, default: Bucket()].blue += blue * weight
        }

        let ranked: [RGB] = buckets.values.sorted { $0.weight > $1.weight }
            .map { (red: $0.red / $0.weight, green: $0.green / $0.weight, blue: $0.blue / $0.weight) }
        guard let first = ranked.first else { return nil }
        let distance = { (a: RGB, b: RGB) in abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue) }
        let second = ranked.dropFirst().first { distance($0, first) > minimumDistinctness } ?? first

        func legible(_ rgb: RGB, maxBrightness: Double) -> HSBColor {
            let colour = HSBColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
            return HSBColor(hue: colour.hue, saturation: min(colour.saturation * 1.1, 0.9), brightness: min(colour.brightness, maxBrightness))
        }
        return AlbumPalette(
            primary: legible(first, maxBrightness: primaryMaxBrightness),
            secondary: legible(second, maxBrightness: secondaryMaxBrightness)
        )
    }
}
