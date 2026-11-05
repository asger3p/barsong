import AppDomain
import SwiftUI

/// A loudness meter as used for mastering: integrated LUFS for the track so far, momentary
/// and short-term loudness and the peak, plus a minute of short-term history against
/// Spotify's normalisation target of −14 LUFS.
enum LoudnessRenderer {
    private static let spotifyTarget = -14.0
    private static let graphRange = -40.0 ... -2.0

    static func draw(_ reading: LoudnessReading, spotifyVolume: Double, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        InstrumentPanel.fillBackground(&context, size: size)
        let inset: CGFloat = 14

        context.draw(InstrumentPanel.label("INTEGRATED", size: 9, weight: .semibold), at: CGPoint(x: inset, y: inset), anchor: .topLeading)
        context.draw(
            Text(value(reading.integrated)).font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundColor(.white)
                + Text(" LUFS").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.5)),
            at: CGPoint(x: inset, y: inset + 12), anchor: .topLeading
        )

        let columns: [(String, String)] = [
            ("MOMENTARY", value(reading.momentary)),
            ("SHORT-TERM", value(reading.shortTerm)),
            ("PEAK dBFS", value(reading.peak)),
        ]
        let columnWidth = (size.width - inset * 2) / CGFloat(columns.count)
        for (index, column) in columns.enumerated() {
            let x = inset + columnWidth * CGFloat(index)
            context.draw(InstrumentPanel.label(column.0, size: 8, weight: .semibold), at: CGPoint(x: x, y: inset + 62), anchor: .topLeading)
            context.draw(Text(column.1).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundColor(.white.opacity(0.9)),
                         at: CGPoint(x: x, y: inset + 74), anchor: .topLeading)
        }

        let hint = spotifyVolume < 99.5 ? "Set Spotify's volume to 100% and turn off its Normalize volume setting for true readings." : nil
        let graph = CGRect(x: inset, y: inset + 110, width: size.width - inset * 2, height: size.height - inset * 2 - 110 - (hint == nil ? 0 : 30))
        drawHistory(reading.history, in: graph, accent: accent, context: &context)
        if let hint {
            context.draw(InstrumentPanel.label(hint, size: 9).italic(), in: CGRect(x: inset, y: size.height - inset - 24, width: size.width - inset * 2, height: 26))
        }
    }

    private static func drawHistory(_ history: [Double?], in rect: CGRect, accent: Color, context: inout GraphicsContext) {
        func y(_ lufs: Double) -> CGFloat {
            let clamped = min(graphRange.upperBound, max(graphRange.lowerBound, lufs))
            return rect.maxY - rect.height * CGFloat((clamped - graphRange.lowerBound) / (graphRange.upperBound - graphRange.lowerBound))
        }
        for level in stride(from: -40.0, through: -10.0, by: 10) {
            context.stroke(InstrumentPanel.line(from: CGPoint(x: rect.minX, y: y(level)), to: CGPoint(x: rect.maxX, y: y(level))),
                           with: .color(InstrumentPanel.gridColour), lineWidth: 0.5)
            context.draw(InstrumentPanel.label("\(Int(level))", size: 8), at: CGPoint(x: rect.maxX, y: y(level) - 1), anchor: .bottomTrailing)
        }
        let targetY = y(spotifyTarget)
        context.stroke(InstrumentPanel.line(from: CGPoint(x: rect.minX, y: targetY), to: CGPoint(x: rect.maxX, y: targetY)),
                       with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        context.draw(InstrumentPanel.label("Spotify −14", size: 8, weight: .semibold, colour: .white.opacity(0.7)),
                     at: CGPoint(x: rect.minX + 2, y: targetY - 2), anchor: .bottomLeading)

        // One minute across the width, newest on the right; gaps where it was silent.
        let step = rect.width / CGFloat(LoudnessMeter.historyLength - 1)
        let startX = rect.maxX - step * CGFloat(history.count - 1)
        var line = Path(), area = Path()
        var runStart: CGFloat?
        for (index, value) in history.enumerated() {
            let x = startX + step * CGFloat(index)
            guard let value else {
                if let start = runStart { closeArea(&area, from: start, to: x - step, bottom: rect.maxY) }
                runStart = nil
                continue
            }
            let point = CGPoint(x: x, y: y(value))
            if runStart == nil {
                runStart = x
                line.move(to: point)
                area.move(to: CGPoint(x: x, y: rect.maxY))
                area.addLine(to: point)
            } else {
                line.addLine(to: point)
                area.addLine(to: point)
            }
        }
        if let start = runStart { closeArea(&area, from: start, to: startX + step * CGFloat(history.count - 1), bottom: rect.maxY) }
        context.fill(area, with: .linearGradient(Gradient(colors: [accent.opacity(0.35), accent.opacity(0.03)]),
                                                 startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
    }

    private static func closeArea(_ area: inout Path, from start: CGFloat, to end: CGFloat, bottom: CGFloat) {
        area.addLine(to: CGPoint(x: end, y: bottom))
        area.closeSubpath()
    }

    private static func value(_ number: Double?) -> String {
        number.map { String(format: "%.1f", $0) } ?? "–"
    }
}
