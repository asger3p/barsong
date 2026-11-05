import AppDomain
import SwiftUI

/// Recent slices stacked into a landscape, like a synth's 3D wavetable display: the newest
/// along the bottom, older ones rising behind it, darker with distance. Every slice spans the
/// full width and is a solid, shaded ridge that hides what's behind it, so the stack reads as hills.
enum RidgeStackRenderer {
    struct Layout {
        /// How many slices a full stack has.
        let depth: Int
        /// Where the front slice's base line sits, and how far up the stack rises (fractions of the height).
        let frontBaseline: Double
        let rise: Double
        let amplitude: Double
        /// Waveforms swing around the base line (-1...1); spectra rise from it (0...1).
        let isCentred: Bool

        static let wavetable = Layout(depth: VisualizerFrame.wavetableDepth, frontBaseline: 0.87, rise: 0.7, amplitude: 0.12, isCentred: true)
        static let waterfall = Layout(depth: VisualizerFrame.waterfallDepth, frontBaseline: 0.97, rise: 0.62, amplitude: 0.32, isCentred: false)
    }

    private static let ground = Color(white: 0.05)

    static func draw(_ slices: [[Float]], layout: Layout, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.clip(to: Path(roundedRect: rect, cornerRadius: InstrumentPanel.cornerRadius))
        context.fill(Path(rect), with: .color(ground))
        guard slices.count > 1 else { return }

        // Back to front, so nearer ridges cover farther ones.
        let count = slices.count
        for (index, slice) in slices.enumerated() {
            let depth = Double(count - 1 - index) / Double(layout.depth - 1) // 0 = newest
            let geometry = SliceGeometry(depth: depth, layout: layout, size: size)
            let points = geometry.points(for: slice)
            let ridge = CurvePath.smooth(through: points, closed: false)
            drawShadedBody(of: ridge, points: points, geometry: geometry, accent: accent, in: &context)

            let nearness = pow(1 - depth, 1.3)
            if index == count - 1 {
                var glow = context
                glow.addFilter(.blur(radius: 4))
                glow.stroke(ridge, with: .color(accent.opacity(0.8)), lineWidth: 3)
                context.stroke(ridge, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            } else {
                context.stroke(ridge, with: .color(accent.opacity(0.12 + 0.6 * nearness)), lineWidth: 0.5 + 0.7 * nearness)
            }
        }
    }

    /// The solid side of a ridge: opaque ground (hiding the slices behind), lit from above, so
    /// crests catch the accent colour and valleys fall into shadow. Farther ridges are dimmer.
    private static func drawShadedBody(of ridge: Path, points: [CGPoint], geometry: SliceGeometry, accent: Color, in context: inout GraphicsContext) {
        guard let first = points.first, let last = points.last else { return }
        var body = ridge
        body.addLine(to: CGPoint(x: last.x, y: geometry.floor))
        body.addLine(to: CGPoint(x: first.x, y: geometry.floor))
        body.closeSubpath()
        context.fill(body, with: .color(ground))
        let light = 0.1 + 0.4 * pow(1 - geometry.depth, 1.5)
        context.fill(body, with: .linearGradient(
            Gradient(colors: [accent.opacity(light), accent.opacity(light * 0.25), .clear]),
            startPoint: CGPoint(x: 0, y: geometry.crest),
            endPoint: CGPoint(x: 0, y: geometry.floor)
        ))
    }

    /// Where one slice sits for its depth (0 = front, 1 = back).
    private struct SliceGeometry {
        let depth: Double
        let baseline: CGFloat
        let width: CGFloat
        let height: CGFloat
        let isCentred: Bool

        init(depth: Double, layout: Layout, size: CGSize) {
            self.depth = depth
            baseline = size.height * (layout.frontBaseline - layout.rise * depth)
            width = size.width
            height = size.height * layout.amplitude
            isCentred = layout.isCentred
        }

        /// The highest and lowest a slice can reach.
        var crest: CGFloat { baseline - height }
        var floor: CGFloat { isCentred ? baseline + height : baseline }

        func points(for slice: [Float]) -> [CGPoint] {
            slice.enumerated().map { index, value in
                CGPoint(x: width * CGFloat(index) / CGFloat(max(slice.count - 1, 1)), y: baseline - height * CGFloat(value))
            }
        }
    }
}
