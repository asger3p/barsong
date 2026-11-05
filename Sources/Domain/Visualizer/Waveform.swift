import Accelerate
import Foundation

package enum Waveform {
    private static let samplesPerPoint = 4
    private static let triggerSmoothing = 24

    /// Picks a window that starts where the (low-passed) signal crosses zero going up, the way
    /// an oscilloscope "triggers", so a steady tone draws in the same place every frame. Then
    /// averages each 4 samples into one point (smoother than skipping samples).
    package static func stable(from samples: [Float], length: Int) -> [Float] {
        let span = length * samplesPerPoint
        guard samples.count >= span else { return [Float](repeating: 0, count: length) }
        let searchEnd = samples.count - span
        // Low-passed copy for finding the trigger, so treble noise doesn't fake crossings.
        let lowPassed = vDSP.slidingWindowSum(samples, usingWindowLength: triggerSmoothing)
        var start = searchEnd // fallback: the most recent window
        for index in stride(from: searchEnd - 1, through: 1, by: -1) where index < lowPassed.count {
            if lowPassed[index - 1] < 0 && lowPassed[index] >= 0 {
                start = index
                break
            }
        }
        return (0..<length).map { point in
            let offset = start + point * samplesPerPoint
            return (samples[offset] + samples[offset + 1] + samples[offset + 2] + samples[offset + 3]) / 4
        }
    }

    /// Moving average along the wave (edges keep their own values) to iron out small wiggles.
    package static func evenedOut(_ points: [Float], width: Int) -> [Float] {
        guard points.count > width else { return points }
        let half = width / 2
        let sums = vDSP.slidingWindowSum(points, usingWindowLength: width)
        return points.indices.map { index in
            guard index >= half, index - half < sums.count else { return points[index] }
            return sums[index - half] / Float(width)
        }
    }
}
