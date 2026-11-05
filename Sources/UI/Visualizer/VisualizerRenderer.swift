import AppDomain
import SwiftUI

/// What a visual needs besides the audio frame.
struct VisualizerSurroundings {
    let accent: Color
    let date: Date
    /// Spotify's own volume, 0–100; loudness readings are only true at 100.
    let spotifyVolume: Double
}

/// Draws a visualizer frame in the chosen style.
enum VisualizerRenderer {
    static func draw(
        _ style: VisualizerStyle,
        frame: VisualizerFrame,
        surroundings: VisualizerSurroundings,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let accent = surroundings.accent
        switch style {
        case .analyzer: AnalyzerRenderer.draw(curve: frame.analyzerCurve, peaks: frame.analyzerPeaks, accent: accent, in: &context, size: size)
        case .spectrogram: SpectrogramRenderer.draw(frame.spectrogram, in: &context, size: size)
        case .waterfall: RidgeStackRenderer.draw(frame.waterfall, layout: .waterfall, accent: accent, in: &context, size: size)
        case .oscilloscope: OscilloscopeRenderer.draw(frame.waveform, accent: accent, in: &context, size: size)
        case .wavetable: RidgeStackRenderer.draw(frame.wavetable, layout: .wavetable, accent: accent, in: &context, size: size)
        case .vectorscope: VectorscopeRenderer.draw(frame.stereoScope, accent: accent, in: &context, size: size)
        case .meters: MetersRenderer.draw(frame.levels, accent: accent, in: &context, size: size)
        case .loudness: LoudnessRenderer.draw(frame.loudness, spotifyVolume: surroundings.spotifyVolume, accent: accent, in: &context, size: size)
        case .chromagram: ChromagramRenderer.draw(history: frame.chromaHistory, key: frame.key, tempo: frame.tempo, accent: accent, in: &context, size: size)
        }
    }
}

/// Shared look for the instrument-style visuals: a dark rounded panel, small labels.
enum InstrumentPanel {
    static let cornerRadius: CGFloat = 8
    static let labelColour = Color.white.opacity(0.45)
    static let gridColour = Color.white.opacity(0.08)

    static func fillBackground(_ context: inout GraphicsContext, size: CGSize, darkness: Double = 0.35) {
        let rect = CGRect(origin: .zero, size: size)
        context.clip(to: Path(roundedRect: rect, cornerRadius: cornerRadius))
        context.fill(Path(rect), with: .color(.black.opacity(darkness)))
    }

    static func label(_ text: String, size: CGFloat = 9, weight: Font.Weight = .medium, colour: Color = labelColour) -> Text {
        Text(text).font(.system(size: size, weight: weight).monospacedDigit()).foregroundColor(colour)
    }

    static func line(from start: CGPoint, to end: CGPoint) -> Path {
        Path { $0.move(to: start); $0.addLine(to: end) }
    }
}

/// A trigger-stabilised oscilloscope: the waveform as a line through the middle, with a soft glow.
enum OscilloscopeRenderer {
    static func draw(_ waveform: [Float], accent: Color, in context: inout GraphicsContext, size: CGSize) {
        guard waveform.count > 1 else { return }
        let midY = size.height / 2
        let points = waveform.enumerated().map { index, sample in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(waveform.count - 1), y: midY - CGFloat(sample) * size.height * 0.4)
        }
        let path = CurvePath.smooth(through: points, closed: false)
        context.stroke(InstrumentPanel.line(from: CGPoint(x: 0, y: midY), to: CGPoint(x: size.width, y: midY)),
                       with: .color(.secondary.opacity(0.3)), lineWidth: 1)
        var glow = context
        glow.addFilter(.blur(radius: 4))
        glow.stroke(path, with: .color(accent.opacity(0.8)), lineWidth: 3)
        context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
}

enum CurvePath {
    /// Curve through the points (quadratic segments between midpoints), instead of straight
    /// lines from point to point, so a wave reads as one smooth stroke.
    static func smooth(through points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        if closed {
            path.move(to: mid(points[points.count - 1], points[0]))
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                path.addQuadCurve(to: mid(points[index], next), control: points[index])
            }
            path.closeSubpath()
        } else {
            path.move(to: points[0])
            for index in 1..<(points.count - 1) {
                path.addQuadCurve(to: mid(points[index], points[index + 1]), control: points[index])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }
}
