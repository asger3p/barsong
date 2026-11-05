import AppDomain
import SwiftUI

/// A studio-EQ style spectrum analyzer: a smooth, filled curve over a log frequency grid, with
/// a thin line holding the recent peaks.
enum AnalyzerRenderer {
    private static let gridFrequencies: [Double] = [50, 100, 200, 500, 1000, 2000, 5000, 10_000]
    private static let gridLevels = 4
    /// The curve stays below this fraction of the height, leaving room for the labels.
    private static let headroom: CGFloat = 0.9

    static func draw(curve: [Float], peaks: [Float], accent: Color, in context: inout GraphicsContext, size: CGSize) {
        guard curve.count > 2 else { return }
        let rect = CGRect(origin: .zero, size: size)
        context.clip(to: Path(roundedRect: rect, cornerRadius: 8))
        context.fill(Path(rect), with: .color(.black.opacity(0.35)))
        drawGrid(in: &context, size: size)

        let curvePoints = points(curve, size: size)
        let line = CurvePath.smooth(through: curvePoints, closed: false)
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [accent.opacity(0.55), accent.opacity(0.18), accent.opacity(0.03)]),
            startPoint: CGPoint(x: 0, y: size.height * (1 - headroom)),
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

        let peakLine = CurvePath.smooth(through: points(peaks, size: size), closed: false)
        context.stroke(peakLine, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
    }

    /// Values (0...1) spread across the width, log-spaced like the analysis.
    private static func points(_ values: [Float], size: CGSize) -> [CGPoint] {
        values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: size.height * (1 - headroom * CGFloat(value))
            )
        }
    }

    private static func xPosition(of frequency: Double, width: CGFloat) -> CGFloat {
        let range = VisualizerFrame.analyzerRange
        return width * CGFloat(log(frequency / range.low) / log(range.high / range.low))
    }

    private static func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let lineColour = Color.white.opacity(0.07)
        for level in 1...gridLevels {
            let y = size.height * CGFloat(level) / CGFloat(gridLevels + 1)
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(lineColour), lineWidth: 0.5)
        }
        for frequency in gridFrequencies {
            let x = xPosition(of: frequency, width: size.width)
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(lineColour), lineWidth: 0.5)
            let label = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
            context.draw(
                Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(Color.white.opacity(0.35)),
                at: CGPoint(x: x + 2, y: 4), anchor: .topLeading
            )
        }
    }
}
