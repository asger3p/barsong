import AppDomain
import SwiftUI

/// Which notes are sounding over the last seconds: one row per note (C at the bottom, B at
/// the top, any octave), brighter where the note is stronger, newest on the right. The key
/// and tempo are shown on top, and the key's scale notes are marked.
enum ChromagramRenderer {
    private static let header: CGFloat = 58
    private static let labelWidth: CGFloat = 26

    static func draw(history: [[Float]], key: MusicalKey?, tempo: TempoEstimate?, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        InstrumentPanel.fillBackground(&context, size: size)
        drawKey(key, in: &context, size: size)
        drawTempo(tempo, in: &context, size: size)

        let grid = CGRect(x: labelWidth, y: header, width: size.width - labelWidth - 10, height: size.height - header - 12)
        let rowHeight = grid.height / 12
        let scale = key?.scale ?? []
        for note in 0..<12 {
            let rowY = grid.maxY - rowHeight * CGFloat(note + 1)
            let inScale = scale.contains(note)
            context.fill(Path(CGRect(x: grid.minX, y: rowY, width: grid.width, height: rowHeight - 1)),
                         with: .color(.white.opacity(inScale ? 0.06 : 0.025)))
            context.draw(
                InstrumentPanel.label(MusicalKey.noteNames[note], size: 9, weight: inScale ? .bold : .medium,
                                      colour: inScale ? .white.opacity(0.85) : InstrumentPanel.labelColour),
                at: CGPoint(x: labelWidth - 6, y: rowY + rowHeight / 2), anchor: .trailing
            )
        }

        guard !history.isEmpty else { return }
        let columnWidth = grid.width / CGFloat(VisualizerFrame.chromaHistoryLength)
        let startX = grid.maxX - columnWidth * CGFloat(history.count)
        for (column, chroma) in history.enumerated() {
            let x = startX + columnWidth * CGFloat(column)
            for (note, strength) in chroma.enumerated() where strength > 0.05 {
                let rowY = grid.maxY - rowHeight * CGFloat(note + 1)
                context.fill(Path(CGRect(x: x, y: rowY, width: columnWidth + 0.5, height: rowHeight - 1)),
                             with: .color(accent.opacity(Double(pow(strength, 1.5)))))
            }
        }
    }

    private static func drawKey(_ key: MusicalKey?, in context: inout GraphicsContext, size: CGSize) {
        let certainty = key.map { $0.confidence > 0.75 ? "clear" : $0.confidence > 0.5 ? "likely" : "unsure" }
        context.draw(InstrumentPanel.label(certainty.map { "KEY · \($0)" } ?? "KEY", size: 9, weight: .semibold),
                     at: CGPoint(x: 14, y: 12), anchor: .topLeading)
        context.draw(Text(key?.name ?? "Listening…").font(.system(size: 22, weight: .bold)).foregroundColor(key == nil ? .white.opacity(0.5) : .white),
                     at: CGPoint(x: 14, y: 24), anchor: .topLeading)
    }

    private static func drawTempo(_ tempo: TempoEstimate?, in context: inout GraphicsContext, size: CGSize) {
        context.draw(InstrumentPanel.label("TEMPO", size: 9, weight: .semibold), at: CGPoint(x: size.width - 14, y: 12), anchor: .topTrailing)
        let bpm = tempo.map { String(format: "%.0f", $0.bpm) } ?? "–"
        context.draw(
            Text(bpm).font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundColor(tempo == nil ? .white.opacity(0.5) : .white)
                + Text(" BPM").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5)),
            at: CGPoint(x: size.width - 14, y: 24), anchor: .topTrailing
        )
    }
}
