import Accelerate
import Foundation

/// A detected tempo.
package struct TempoEstimate: Equatable, Sendable {
    package let bpm: Double
    /// How clearly the beat stands out, 0...1.
    package let confidence: Double

    package init(bpm: Double, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }
}

/// Finds the tempo from an onset-strength signal (how sharply the sound changes, sampled
/// 100 times a second): the strongest repeating interval between 60 and 200 BPM, weighted
/// towards the tempos people tend to tap along to, and steadied over recent estimates.
package final class TempoDetector {
    package static let envelopeRate = 100.0
    private static let window = 8.0 // seconds analysed
    private static let minimumHistory = 4.0 // seconds before a first estimate
    private static let estimateInterval = 0.5 // seconds
    private static let bpmRange = 60.0...200.0
    /// The fastest tempo a half-time reading is doubled to.
    private static let doubleTimeLimit = 180.0
    private static let steadyingCount = 7

    package private(set) var tempo: TempoEstimate?

    private var envelope: [Float] = []
    private var slotTime = 0.0
    private var slotsSinceEstimate = 0
    private var recentEstimates: [TempoEstimate] = []

    package init() {}

    package func reset() {
        envelope = []
        slotTime = 0
        slotsSinceEstimate = 0
        recentEstimates = []
        tempo = nil
    }

    /// Adds onset strength measured over `duration` seconds, spread onto the 100 Hz grid.
    package func add(onsetStrength: Float, duration: TimeInterval) {
        slotTime += duration * Self.envelopeRate
        while slotTime >= 1 {
            slotTime -= 1
            envelope.append(onsetStrength)
            slotsSinceEstimate += 1
        }
        let capacity = Int(Self.window * Self.envelopeRate)
        if envelope.count > capacity { envelope.removeFirst(envelope.count - capacity) }

        guard envelope.count >= Int(Self.minimumHistory * Self.envelopeRate),
              slotsSinceEstimate >= Int(Self.estimateInterval * Self.envelopeRate)
        else { return }
        slotsSinceEstimate = 0
        guard let estimate = Self.estimate(envelope: envelope, rate: Self.envelopeRate) else { return }
        recentEstimates.append(estimate)
        if recentEstimates.count > Self.steadyingCount { recentEstimates.removeFirst() }
        let sorted = recentEstimates.sorted { $0.bpm < $1.bpm }
        tempo = sorted[sorted.count / 2] // the median, so one odd estimate doesn't jump the display
    }

    /// The tempo of an onset-strength signal, by autocorrelation.
    package static func estimate(envelope: [Float], rate: Double) -> TempoEstimate? {
        let smoothed = smoothed(envelope)
        let mean = smoothed.reduce(0, +) / Float(max(smoothed.count, 1))
        let centred = smoothed.map { $0 - mean }
        let energy = vDSP.sumOfSquares(centred)
        guard energy > 1e-9 else { return nil }

        func autocorrelation(_ lag: Int) -> Float {
            guard lag < centred.count else { return 0 }
            return vDSP.dot(Array(centred[lag...]), Array(centred[..<(centred.count - lag)])) / energy
        }
        let shortestLag = Int((60 / bpmRange.upperBound * rate).rounded(.down))
        let longestLag = Int((60 / bpmRange.lowerBound * rate).rounded(.up))
        guard longestLag + 1 < centred.count else { return nil }
        let correlations = (0...longestLag + 1).map(autocorrelation)

        var bestLag = shortestLag, bestScore = -Float.infinity
        for lag in shortestLag...longestLag {
            let bpm = 60 * rate / Double(lag)
            // Log-normal preference around 120 BPM, one octave wide, as in common beat trackers.
            let preference = Float(exp(-0.5 * pow(log2(bpm / 120), 2)))
            // Half-tempo support: a real beat repeats at twice its interval too.
            let support = 2 * lag < correlations.count ? correlations[2 * lag] : autocorrelation(2 * lag)
            let score = (correlations[lag] + 0.5 * support) * preference
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        // Half-time or double-time? When there's an equally strong beat halfway, the faster
        // tempo is the one people count (174 BPM drum & bass rather than 87).
        let halfLag = Int((Double(bestLag) / 2).rounded())
        if halfLag >= shortestLag, halfLag > 1, 60 * rate / Double(halfLag) <= doubleTimeLimit,
           correlations[halfLag] >= 0.9 * correlations[bestLag] {
            bestLag = halfLag
        }
        // Sub-sample refinement by fitting a parabola through the peak and its neighbours.
        let before = correlations[bestLag - 1], peak = correlations[bestLag], after = correlations[bestLag + 1]
        let curvature = before - 2 * peak + after
        let offset = curvature < 0 ? Double(0.5 * (before - after) / curvature) : 0
        let bpm = 60 * rate / (Double(bestLag) + max(-0.5, min(0.5, offset)))
        return TempoEstimate(bpm: bpm, confidence: Double(max(0, min(1, peak))))
    }
}

extension TempoDetector {
    /// A short triangular blur (about 50 ms), so a beat that falls between two envelope
    /// steps still lines up with the next one.
    static func smoothed(_ envelope: [Float]) -> [Float] {
        let weights: [Float] = [1, 2, 3, 2, 1]
        let half = weights.count / 2, total = weights.reduce(0, +)
        return envelope.indices.map { index in
            var sum: Float = 0
            for (offset, weight) in weights.enumerated() {
                let source = index + offset - half
                if envelope.indices.contains(source) { sum += envelope[source] * weight }
            }
            return sum / total
        }
    }
}

/// How sharply the spectrum is rising: the summed increase in log magnitude since the last
/// spectrum (spectral flux), which peaks on drum hits and note starts.
package struct OnsetStrength {
    private var previous: [Float] = []

    package init() {}

    package mutating func next(from magnitudes: [Float]) -> Float {
        let compressed = magnitudes.map { log1p(1000 * $0) }
        defer { previous = compressed }
        guard previous.count == compressed.count else { return 0 }
        return zip(compressed, previous).reduce(Float(0)) { $0 + max(0, $1.0 - $1.1) }
    }
}
