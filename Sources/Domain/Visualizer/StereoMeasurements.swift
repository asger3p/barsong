import Accelerate
import Foundation

/// One chunk of stereo audio.
package struct StereoSamples: Sendable {
    package let left: [Float]
    package let right: [Float]

    package init(left: [Float], right: [Float]) {
        self.left = left
        self.right = right
    }

    /// The same signal in both channels.
    package init(mono: [Float]) {
        self.init(left: mono, right: mono)
    }

    package var mono: [Float] {
        guard left.count == right.count else { return left }
        return vDSP.multiply(0.5, vDSP.add(left, right))
    }
}

/// Peak and RMS of one channel in dBFS, with the ballistics of a studio meter: peaks jump up
/// and fall back at a steady rate, RMS is averaged over about 300 ms, and the highest peak
/// is held for a moment before it falls too.
package struct ChannelLevel: Equatable, Sendable {
    package static let floor: Float = -60
    private static let fallRate: Float = 24 // dB per second
    private static let rmsTime = 0.3 // seconds
    private static let holdTime = 1.5 // seconds

    package private(set) var peak: Float = floor
    package private(set) var rms: Float = floor
    package private(set) var hold: Float = floor
    private var meanSquare: Float = 0
    private var holdSetAt: Date = .distantPast

    package init() {}

    package mutating func update(with samples: [Float], duration: TimeInterval, at now: Date) {
        guard !samples.isEmpty else { return }
        let fall = Self.fallRate * Float(duration)
        let chunkPeak = Self.decibels(vDSP.maximumMagnitude(samples))
        peak = max(chunkPeak, peak - fall)

        let blend = Float(1 - exp(-duration / Self.rmsTime))
        meanSquare += (vDSP.meanSquare(samples) - meanSquare) * blend
        rms = Self.decibels(sqrt(meanSquare))

        if peak >= hold {
            hold = peak
            holdSetAt = now
        } else if now.timeIntervalSince(holdSetAt) > Self.holdTime {
            hold = max(peak, hold - fall)
        }
    }

    static func decibels(_ amplitude: Float) -> Float {
        max(floor, 20 * log10(max(amplitude, 1e-9)))
    }
}

package struct StereoLevels: Equatable, Sendable {
    package var left = ChannelLevel()
    package var right = ChannelLevel()

    package init() {}
}

/// Recent left/right sample pairs for the vectorscope, plus the phase correlation.
package struct StereoScope: Sendable {
    package static let pointCount = 512

    /// Scaled so the loudest recent point sits near the edge.
    package private(set) var left = [Float](repeating: 0, count: pointCount)
    package private(set) var right = [Float](repeating: 0, count: pointCount)
    /// +1: mono, 0: wide or unrelated, −1: out of phase (cancels in mono).
    package private(set) var correlation: Float = 1
    /// −1: all left, 0: centred, +1: all right (from the channels' energy).
    package private(set) var balance: Float = 0
    private var gain: Float = 1

    package init() {}

    package mutating func update(with samples: StereoSamples) {
        let count = min(samples.left.count, samples.right.count)
        guard count > 0 else { return }
        let step = max(1, count / Self.pointCount)
        let indices = Array(stride(from: max(0, count - step * Self.pointCount), to: count, by: step).suffix(Self.pointCount))
        let newLeft = indices.map { samples.left[$0] }
        let newRight = indices.map { samples.right[$0] }

        let peak = max(newLeft.map(abs).max() ?? 0, newRight.map(abs).max() ?? 0, 0.02)
        let targetGain = min(0.9 / peak, 40)
        gain = targetGain < gain ? targetGain : gain * 0.97 + targetGain * 0.03
        left = Array((left + newLeft.map { $0 * gain }).suffix(Self.pointCount))
        right = Array((right + newRight.map { $0 * gain }).suffix(Self.pointCount))

        if let chunkCorrelation = Self.correlation(samples.left, samples.right) {
            correlation = correlation * 0.85 + chunkCorrelation * 0.15
        }
        if let chunkBalance = Self.balance(samples.left, samples.right) {
            balance = balance * 0.9 + chunkBalance * 0.1
        }
    }

    /// Right energy minus left energy, over both; nil in silence.
    static func balance(_ left: [Float], _ right: [Float]) -> Float? {
        let leftEnergy = vDSP.sumOfSquares(left), rightEnergy = vDSP.sumOfSquares(right)
        guard leftEnergy + rightEnergy > 1e-9 else { return nil }
        return (rightEnergy - leftEnergy) / (rightEnergy + leftEnergy)
    }

    /// Pearson-style correlation without removing the mean (as phase meters do); nil in silence.
    static func correlation(_ left: [Float], _ right: [Float]) -> Float? {
        let count = min(left.count, right.count)
        guard count > 0 else { return nil }
        let l = Array(left.prefix(count)), r = Array(right.prefix(count))
        let energy = vDSP.sumOfSquares(l) * vDSP.sumOfSquares(r)
        guard energy > 1e-12 else { return nil }
        return vDSP.dot(l, r) / sqrt(energy)
    }
}
