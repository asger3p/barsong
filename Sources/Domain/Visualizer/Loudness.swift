import Foundation

/// A second-order IIR filter (transposed direct form II).
package struct Biquad: Sendable {
    package let b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    package init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    package mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }
}

/// The K-weighting of ITU-R BS.1770: a high shelf for the head's acoustic effect, then a high
/// pass (the "RLB" curve). Coefficients follow the standard's analogue design (as in
/// libebur128), so they're right at any sample rate.
package struct KWeighting: Sendable {
    package private(set) var shelf: Biquad
    package private(set) var highPass: Biquad

    package init(sampleRate: Double) {
        var k = tan(.pi * 1681.974450955533 / sampleRate)
        var q = 0.7071752369554196
        let shelfGain = pow(10, 3.999843853973347 / 20)
        let shelfBoost = pow(shelfGain, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        shelf = Biquad(
            b0: (shelfGain + shelfBoost * k / q + k * k) / a0,
            b1: 2 * (k * k - shelfGain) / a0,
            b2: (shelfGain - shelfBoost * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0
        )
        k = tan(.pi * 38.13547087602444 / sampleRate)
        q = 0.5003270373238773
        a0 = 1 + k / q + k * k
        highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
    }

    package mutating func process(_ sample: Double) -> Double {
        highPass.process(shelf.process(sample))
    }
}

/// Loudness in LUFS as streaming services measure it (ITU-R BS.1770-4 / EBU R 128).
package struct LoudnessReading: Equatable, Sendable {
    /// Over the last 400 ms. Nil until there's enough audio, or in silence.
    package var momentary: Double?
    /// Over the last 3 s.
    package var shortTerm: Double?
    /// Gated average since the track started.
    package var integrated: Double?
    /// Highest sample since the track started, in dBFS.
    package var peak: Double?
    /// Short-term loudness every 0.2 s, oldest first (nil where it was silent).
    package var history: [Double?] = []

    package init() {}
}

/// Measures loudness of a stereo signal block by block.
package final class LoudnessMeter {
    package static let historyLength = 300 // one minute at 0.2 s
    private static let hopDuration = 0.1
    private static let momentaryHops = 4
    private static let shortTermHops = 30
    private static let hopsPerHistoryPoint = 2
    private static let absoluteGate = -70.0
    private static let relativeGate = -10.0

    package private(set) var reading = LoudnessReading()

    private var sampleRate = 0.0
    private var filters: [KWeighting] = []
    private var hopEnergy = 0.0
    private var hopSampleCount = 0
    private var samplesPerHop = 0
    /// Mean square per hop (summed over both channels), newest last.
    private var recentHops: [Double] = []
    /// 400 ms blocks (overlapping by 75 %) since the track started, for the integrated value.
    private var blockEnergies: [Double] = []
    private var hopsSinceHistoryPoint = 0
    private var peakAmplitude: Float = 0

    package init() {}

    /// Starts a fresh measurement (new track).
    package func reset() {
        recentHops = []
        blockEnergies = []
        hopEnergy = 0
        hopSampleCount = 0
        hopsSinceHistoryPoint = 0
        peakAmplitude = 0
        reading = LoudnessReading()
    }

    package func process(_ samples: StereoSamples, sampleRate: Double) {
        if sampleRate != self.sampleRate {
            self.sampleRate = sampleRate
            filters = [KWeighting(sampleRate: sampleRate), KWeighting(sampleRate: sampleRate)]
            samplesPerHop = Int(sampleRate * Self.hopDuration)
        }
        for index in 0..<min(samples.left.count, samples.right.count) {
            let left = filters[0].process(Double(samples.left[index]))
            let right = filters[1].process(Double(samples.right[index]))
            hopEnergy += left * left + right * right
            hopSampleCount += 1
            if hopSampleCount == samplesPerHop { finishHop() }
        }
        peakAmplitude = max(peakAmplitude, samples.left.map(abs).max() ?? 0, samples.right.map(abs).max() ?? 0)
        reading.peak = peakAmplitude > 0 ? 20 * log10(Double(peakAmplitude)) : nil
    }

    private func finishHop() {
        recentHops.append(hopEnergy / Double(hopSampleCount))
        if recentHops.count > Self.shortTermHops { recentHops.removeFirst() }
        hopEnergy = 0
        hopSampleCount = 0

        reading.momentary = loudness(ofMeanSquare: mean(recentHops.suffix(Self.momentaryHops)), needing: Self.momentaryHops)
        reading.shortTerm = loudness(ofMeanSquare: mean(recentHops.suffix(Self.shortTermHops)), needing: Self.shortTermHops)
        if recentHops.count >= Self.momentaryHops {
            blockEnergies.append(mean(recentHops.suffix(Self.momentaryHops)))
            reading.integrated = Self.gatedLoudness(of: blockEnergies)
        }
        hopsSinceHistoryPoint += 1
        if hopsSinceHistoryPoint == Self.hopsPerHistoryPoint {
            hopsSinceHistoryPoint = 0
            reading.history.append(reading.shortTerm)
            if reading.history.count > Self.historyLength { reading.history.removeFirst() }
        }
    }

    private func loudness(ofMeanSquare meanSquare: Double, needing hops: Int) -> Double? {
        guard recentHops.count >= hops else { return nil }
        let value = Self.loudness(ofMeanSquare: meanSquare)
        return value > Self.absoluteGate ? value : nil
    }

    /// The integrated value: blocks under -70 LUFS are dropped, then blocks more than 10 LU
    /// below the average of the rest.
    static func gatedLoudness(of blocks: [Double]) -> Double? {
        let audible = blocks.filter { loudness(ofMeanSquare: $0) > absoluteGate }
        guard !audible.isEmpty else { return nil }
        let threshold = loudness(ofMeanSquare: audible.reduce(0, +) / Double(audible.count)) + relativeGate
        let gated = audible.filter { loudness(ofMeanSquare: $0) > threshold }
        guard !gated.isEmpty else { return nil }
        return loudness(ofMeanSquare: gated.reduce(0, +) / Double(gated.count))
    }

    static func loudness(ofMeanSquare meanSquare: Double) -> Double {
        -0.691 + 10 * log10(max(meanSquare, 1e-12))
    }

    private func mean(_ values: ArraySlice<Double>) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
