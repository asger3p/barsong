import Accelerate
import Foundation

/// A reusable FFT of a fixed size with its Hann window.
package struct FrequencyAnalyzer {
    package let size: Int
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]

    package init(size: Int) {
        self.size = size
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size))), radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    }

    /// Amplitude per frequency bin (size / 2 bins) of the last `size` samples.
    package func magnitudes(of samples: [Float]) -> [Float] {
        let input = samples.count == size ? samples : Array(samples.suffix(size))
        let half = size / 2
        let windowed = vDSP.multiply(input, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { windowedPointer in
                    windowedPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft?.forward(input: split, output: &split)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        return vDSP.multiply(1 / Float(size), magnitudes)
    }
}

package enum SpectrumBands {
    /// Groups bins into log-spaced bands (how we hear pitch) and maps each band's level in dB
    /// to 0...1, tilted +3 dB per octave so treble shows as much as bass, as in most analyzers.
    package static func logBands(_ magnitudes: [Float], count: Int, sampleRate: Double, low: Double, high: Double) -> [Float] {
        let binWidth = sampleRate / Double(magnitudes.count * 2)
        return (0..<count).map { band in
            let lowFrequency = low * pow(high / low, Double(band) / Double(count))
            let highFrequency = low * pow(high / low, Double(band + 1) / Double(count))
            let centre = sqrt(lowFrequency * highFrequency)
            let peak: Float
            if highFrequency - lowFrequency < binWidth * 2 {
                // Narrow (bass) band: read between the two nearest bins, so neighbouring bands
                // differ instead of showing the same bin as a blocky step.
                let exact = min(max(centre / binWidth, 1), Double(magnitudes.count - 2))
                let below = Int(exact), fraction = Float(exact - Double(below))
                peak = magnitudes[below] * (1 - fraction) + magnitudes[below + 1] * fraction
            } else {
                let firstBin = min(max(Int(lowFrequency / binWidth), 1), magnitudes.count - 1)
                let lastBin = min(max(Int(highFrequency / binWidth), firstBin + 1), magnitudes.count)
                peak = magnitudes[firstBin..<lastBin].max() ?? 0
            }
            let decibels = 20 * log10(Double(max(peak, 1e-9))) + 3 * log2(centre / 1000)
            return Float(max(0, min(1, (decibels + 66) / 54)))
        }
    }
}
