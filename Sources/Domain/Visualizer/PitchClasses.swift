import Foundation

/// A musical key, like "A minor".
package struct MusicalKey: Equatable, Sendable {
    package static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    /// 0 = C … 11 = B.
    package let tonic: Int
    package let isMinor: Bool
    /// How well the music fits this key, 0...1.
    package let confidence: Double

    package init(tonic: Int, isMinor: Bool, confidence: Double) {
        self.tonic = tonic
        self.isMinor = isMinor
        self.confidence = confidence
    }

    package var name: String { "\(Self.noteNames[tonic]) \(isMinor ? "minor" : "major")" }

    /// Pitch classes of the key's scale (natural minor for minor keys).
    package var scale: Set<Int> {
        let steps = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return Set(steps.map { ($0 + tonic) % 12 })
    }
}

package enum PitchClasses {
    /// The range whose notes are counted: bass to the top of most melodies.
    private static let range = 55.0...2000.0

    /// How strongly each of the 12 notes (C…B, any octave) sounds, 0...1 relative to the
    /// strongest. Uses energy per FFT bin, assigned to the nearest note.
    package static func chroma(from magnitudes: [Float], fftSize: Int, sampleRate: Double) -> [Float] {
        var energy = [Float](repeating: 0, count: 12)
        let binWidth = sampleRate / Double(fftSize)
        let firstBin = max(1, Int(range.lowerBound / binWidth))
        let lastBin = min(magnitudes.count - 1, Int(range.upperBound / binWidth))
        guard firstBin <= lastBin else { return energy }
        for bin in firstBin...lastBin {
            let midiNote = 69 + 12 * log2(Double(bin) * binWidth / 440)
            let pitchClass = ((Int(midiNote.rounded()) % 12) + 12) % 12
            energy[pitchClass] += magnitudes[bin] * magnitudes[bin]
        }
        let strongest = energy.max() ?? 0
        return strongest > 0 ? energy.map { $0 / strongest } : energy
    }
}

/// Guesses the key from a chroma profile with the Krumhansl–Kessler key profiles: how much
/// each note is felt to belong to a major or minor key, correlated with what's sounding.
package enum KeyDetector {
    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    package static func key(for chroma: [Float]) -> MusicalKey? {
        guard chroma.count == 12, chroma.contains(where: { $0 > 0 }) else { return nil }
        let values = chroma.map(Double.init)
        var best: MusicalKey?
        for tonic in 0..<12 {
            for isMinor in [false, true] {
                let profile = isMinor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
                let score = correlation(values, rotated)
                if score > (best?.confidence ?? -.infinity) {
                    best = MusicalKey(tonic: tonic, isMinor: isMinor, confidence: score)
                }
            }
        }
        return best
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
        var covariance = 0.0, varianceA = 0.0, varianceB = 0.0
        for index in a.indices {
            let da = a[index] - meanA, db = b[index] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return covariance / sqrt(varianceA * varianceB)
    }
}
