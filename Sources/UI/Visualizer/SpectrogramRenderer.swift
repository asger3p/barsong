import AppDomain
import SwiftUI

/// Scrolling frequency-over-time heatmap (newest on the right, low notes at the bottom) in
/// magma colours, drawn pixel for pixel: the intensities are an indexed-colour image whose
/// colour table is the palette, so nothing is converted per frame.
enum SpectrogramRenderer {
    private static let colorSpace: CGColorSpace? = {
        let table = (0..<256).flatMap { step -> [UInt8] in
            // Extra contrast, so the background sinks to black and partials stand out.
            let (red, green, blue) = magma(pow(Double(step) / 255, 1.8))
            return [red, green, blue]
        }
        return CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: table)
    }()

    static func draw(_ history: SpectrogramHistory, in context: inout GraphicsContext, size: CGSize) {
        let width = SpectrogramHistory.width, height = SpectrogramHistory.height
        guard let colorSpace,
              let provider = CGDataProvider(data: Data(history.intensities) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return }
        let rect = CGRect(origin: .zero, size: size)
        context.clip(to: Path(roundedRect: rect, cornerRadius: 8))
        context.draw(Image(decorative: image, scale: 2), in: rect)
    }

    /// Approximation of matplotlib's "magma": black → purple → pink-red → orange → pale yellow.
    static func magma(_ value: Double) -> (UInt8, UInt8, UInt8) {
        let stops: [(Double, Double, Double)] = [
            (0.00, 0.00, 0.02), (0.23, 0.06, 0.44), (0.55, 0.16, 0.51), (0.87, 0.29, 0.41), (0.99, 0.62, 0.42), (0.99, 0.99, 0.75),
        ]
        let position = max(0, min(1, value)) * Double(stops.count - 1)
        let lower = Int(position), upper = min(lower + 1, stops.count - 1)
        let t = position - Double(lower)
        func mix(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, (a + (b - a) * t) * 255))) }
        return (mix(stops[lower].0, stops[upper].0), mix(stops[lower].1, stops[upper].1), mix(stops[lower].2, stops[upper].2))
    }
}
