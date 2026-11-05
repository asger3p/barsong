import AppDomain
import SwiftUI

/// Studio level meters for left and right: the RMS body, the peak above it, a held peak line,
/// on a dBFS scale that turns warm towards 0 dB.
enum MetersRenderer {
    private static let marks: [Float] = [0, -3, -6, -9, -12, -18, -24, -36, -48, -60]
    private static let top: CGFloat = 44, bottom: CGFloat = 24
    private static let barWidth: CGFloat = 46

    static func draw(_ levels: StereoLevels, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        InstrumentPanel.fillBackground(&context, size: size)
        let meterHeight = size.height - top - bottom
        func y(_ decibels: Float) -> CGFloat {
            top + meterHeight * CGFloat(min(0, max(ChannelLevel.floor, decibels)) / ChannelLevel.floor)
        }

        let gap: CGFloat = 18
        let totalWidth = barWidth * 2 + gap
        let leftX = (size.width - totalWidth) / 2 + 14
        let rightX = leftX + barWidth + gap

        for mark in marks {
            let markY = y(mark)
            context.stroke(InstrumentPanel.line(from: CGPoint(x: leftX - 6, y: markY), to: CGPoint(x: rightX + barWidth, y: markY)),
                           with: .color(InstrumentPanel.gridColour), lineWidth: 0.5)
            context.draw(InstrumentPanel.label(mark == 0 ? "0" : "\(Int(mark))"), at: CGPoint(x: leftX - 9, y: markY), anchor: .trailing)
        }

        let gradient = Gradient(stops: [
            .init(color: accent, location: 0),
            .init(color: accent, location: 0.8),
            .init(color: Color(red: 1, green: 0.78, blue: 0.2), location: 0.9),
            .init(color: Color(red: 1, green: 0.3, blue: 0.25), location: 1),
        ])
        for (level, x, name) in [(levels.left, leftX, "L"), (levels.right, rightX, "R")] {
            let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: CGPoint(x: 0, y: y(ChannelLevel.floor)), endPoint: CGPoint(x: 0, y: y(0)))
            context.fill(Path(roundedRect: CGRect(x: x, y: top, width: barWidth, height: meterHeight), cornerRadius: 3),
                         with: .color(.white.opacity(0.05)))
            // Peak as a translucent band above the solid RMS body.
            context.opacity = 0.4
            context.fill(Path(CGRect(x: x, y: y(level.peak), width: barWidth, height: y(ChannelLevel.floor) - y(level.peak))), with: shading)
            context.opacity = 1
            context.fill(Path(CGRect(x: x, y: y(level.rms), width: barWidth, height: y(ChannelLevel.floor) - y(level.rms))), with: shading)
            if level.hold > ChannelLevel.floor {
                context.fill(Path(CGRect(x: x, y: y(level.hold) - 1, width: barWidth, height: 2)), with: .color(.white.opacity(0.85)))
            }
            context.draw(InstrumentPanel.label(format(level.hold), size: 10, weight: .semibold, colour: level.hold > -1 ? Color(red: 1, green: 0.4, blue: 0.35) : .white.opacity(0.8)),
                         at: CGPoint(x: x + barWidth / 2, y: top - 8), anchor: .bottom)
            context.draw(InstrumentPanel.label(name, size: 10, weight: .bold), at: CGPoint(x: x + barWidth / 2, y: size.height - bottom + 8), anchor: .top)
        }
        context.draw(InstrumentPanel.label("dBFS", size: 8, weight: .semibold), at: CGPoint(x: 10, y: 10), anchor: .topLeading)
        context.draw(InstrumentPanel.label("RMS solid · peak light", size: 8), at: CGPoint(x: size.width - 10, y: 10), anchor: .topTrailing)
    }

    private static func format(_ decibels: Float) -> String {
        decibels <= ChannelLevel.floor ? "−∞" : String(format: "%.1f", decibels)
    }
}
