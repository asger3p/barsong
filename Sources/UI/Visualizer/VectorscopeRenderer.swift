import AppDomain
import SwiftUI

/// A goniometer: every recent left/right sample pair as a dot, turned 45° so mono stands
/// straight up (M), sound on one side only leans along L or R, and out-of-phase sound lies
/// sideways (S). Underneath, the two meters that usually go with it:
/// - correlation, by convention from −1 (out of phase) on the left through 0 (unrelated,
///   very wide) in the middle to +1 (mono) on the right;
/// - balance, centred when left and right are equally loud.
enum VectorscopeRenderer {
    private static let dotSize: CGFloat = 1.6
    private static let meterRowHeight: CGFloat = 46
    private static let scopeToMeters: CGFloat = 18
    private static let inset: CGFloat = 16

    static func draw(_ scope: StereoScope, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        InstrumentPanel.fillBackground(&context, size: size)
        // Scope and meters as one block, centred vertically.
        let metersHeight = meterRowHeight * 2
        let side = min(size.width - inset * 2, size.height - metersHeight - scopeToMeters - inset * 2)
        let top = (size.height - side - scopeToMeters - metersHeight) / 2
        let centre = CGPoint(x: size.width / 2, y: top + side / 2)
        let radius = side / 2
        drawGuides(centre: centre, radius: radius, in: &context)
        drawDots(scope, centre: centre, radius: radius, accent: accent, in: &context)

        let metersTop = top + side + scopeToMeters
        let outOfPhase = Color(red: 1, green: 0.35, blue: 0.3)
        drawMeter(
            title: "Correlation", value: scope.correlation,
            reading: "\(String(format: "%+.2f", scope.correlation)) · \(correlationDescription(scope.correlation))",
            ends: ("−1", "+1"), fillsFromCentre: false,
            colour: scope.correlation < 0 ? outOfPhase : accent,
            rowTop: metersTop, in: &context, size: size
        )
        drawMeter(
            title: "Balance", value: scope.balance,
            reading: balanceDescription(scope.balance),
            ends: ("L", "R"), fillsFromCentre: true,
            colour: accent,
            rowTop: metersTop + meterRowHeight, in: &context, size: size
        )
    }

    private static func drawDots(_ scope: StereoScope, centre: CGPoint, radius: CGFloat, accent: Color, in context: inout GraphicsContext) {
        // L and R are ±1; mid (L+R) goes up, side (R−L) goes right, each over √2.
        var dots = Path()
        for index in scope.left.indices {
            let left = CGFloat(scope.left[index]), right = CGFloat(scope.right[index])
            let x = centre.x + (right - left) / sqrt(2) * radius
            let y = centre.y - (left + right) / sqrt(2) * radius
            dots.addEllipse(in: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
        }
        var glow = context
        glow.addFilter(.blur(radius: 3))
        glow.fill(dots, with: .color(accent.opacity(0.5)))
        context.fill(dots, with: .color(accent.opacity(0.85)))
    }

    private static func drawGuides(centre: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        let diamond = Path { path in
            path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
            path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
            path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
            path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
            path.closeSubpath()
        }
        context.stroke(diamond, with: .color(InstrumentPanel.gridColour), lineWidth: 0.8)
        let diagonal = radius / sqrt(2)
        let guides = [
            (CGPoint(x: centre.x, y: centre.y - radius), CGPoint(x: centre.x, y: centre.y + radius)), // M
            (CGPoint(x: centre.x - radius, y: centre.y), CGPoint(x: centre.x + radius, y: centre.y)), // S
            (CGPoint(x: centre.x - diagonal, y: centre.y - diagonal), CGPoint(x: centre.x + diagonal, y: centre.y + diagonal)), // L
            (CGPoint(x: centre.x + diagonal, y: centre.y - diagonal), CGPoint(x: centre.x - diagonal, y: centre.y + diagonal)), // R
        ]
        for (start, end) in guides {
            context.stroke(InstrumentPanel.line(from: start, to: end), with: .color(InstrumentPanel.gridColour), lineWidth: 0.6)
        }
        context.draw(InstrumentPanel.label("M"), at: CGPoint(x: centre.x, y: centre.y - radius - 2), anchor: .bottom)
        context.draw(InstrumentPanel.label("L"), at: CGPoint(x: centre.x - diagonal - 4, y: centre.y - diagonal - 4), anchor: .bottomTrailing)
        context.draw(InstrumentPanel.label("R"), at: CGPoint(x: centre.x + diagonal + 4, y: centre.y - diagonal - 4), anchor: .bottomLeading)
    }

    /// A horizontal meter from −1 to +1: a title and reading above, a track with a marker.
    /// Balance fills outward from the centre; correlation fills from the left end, like a
    /// phase meter.
    private static func drawMeter(
        title: String, value: Float, reading: String, ends: (String, String), fillsFromCentre: Bool,
        colour: Color, rowTop: CGFloat, in context: inout GraphicsContext, size: CGSize
    ) {
        let left = inset, right = size.width - inset, width = right - left
        let trackY = rowTop + 22
        context.draw(InstrumentPanel.label(title.uppercased(), size: 8, weight: .semibold), at: CGPoint(x: left, y: rowTop + 4), anchor: .topLeading)
        context.draw(InstrumentPanel.label(reading, size: 10, weight: .semibold, colour: .white.opacity(0.8)),
                     at: CGPoint(x: right, y: rowTop + 3), anchor: .topTrailing)

        context.fill(Path(roundedRect: CGRect(x: left, y: trackY - 2, width: width, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.1)))
        let markerX = left + width * CGFloat((max(-1, min(1, value)) + 1) / 2)
        let fillStart = fillsFromCentre ? left + width / 2 : left
        let fill = CGRect(x: min(fillStart, markerX), y: trackY - 2, width: abs(markerX - fillStart), height: 4)
        context.fill(Path(roundedRect: fill, cornerRadius: 2), with: .color(colour.opacity(0.6)))
        context.fill(Path(ellipseIn: CGRect(x: markerX - 4, y: trackY - 4, width: 8, height: 8)), with: .color(colour))
        context.draw(InstrumentPanel.label(ends.0, size: 8), at: CGPoint(x: left, y: trackY + 6), anchor: .topLeading)
        context.draw(InstrumentPanel.label(ends.1, size: 8), at: CGPoint(x: right, y: trackY + 6), anchor: .topTrailing)
    }

    private static func correlationDescription(_ correlation: Float) -> String {
        switch correlation {
        case 0.9...: "mono"
        case 0.3..<0.9: "stereo"
        case 0..<0.3: "very wide"
        default: "out of phase"
        }
    }

    private static func balanceDescription(_ balance: Float) -> String {
        let percent = Int((abs(balance) * 100).rounded())
        guard percent >= 2 else { return "centred" }
        return "\(percent)% \(balance < 0 ? "left" : "right")"
    }
}
