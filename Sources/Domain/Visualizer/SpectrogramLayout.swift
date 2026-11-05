import Foundation

/// Maps FFT bins to the spectrogram's pixel rows, Harmor-style: long windows for bass
/// (fine pitch), short ones for treble (sharp in time). Each row reads the resolution
/// meant for its frequency.
package struct SpectrogramLayout: Sendable {
    package struct Resolution: Sendable {
        package let fftSize: Int
        /// Highest row frequency (Hz) that uses this resolution.
        package let upTo: Double
    }

    package struct Row: Equatable, Sendable {
        /// Index into `resolutions`.
        package let resolution: Int
        package let lowBin: Double
        package let highBin: Double
        package let frequency: Double
    }

    package static let resolutions = [
        Resolution(fftSize: 16_384, upTo: 300),
        Resolution(fftSize: 8192, upTo: 2000),
        Resolution(fftSize: 4096, upTo: .infinity),
    ]
    package static let lowestFrequency = 30.0
    package static let highestFrequency = 16_000.0
    /// Samples needed for the longest window.
    package static let longestWindow = resolutions.map(\.fftSize).max()!

    package let sampleRate: Double
    package let rows: [Row]

    /// Rows top (16 kHz) to bottom (30 Hz), log-spaced.
    package init(sampleRate: Double, rowCount: Int = SpectrogramHistory.height) {
        self.sampleRate = sampleRate
        let low = Self.lowestFrequency, high = Self.highestFrequency
        rows = (0..<rowCount).map { row in
            let top = high * pow(low / high, Double(row) / Double(rowCount))
            let bottom = high * pow(low / high, Double(row + 1) / Double(rowCount))
            let centre = sqrt(top * bottom)
            let resolution = Self.resolutions.firstIndex { centre <= $0.upTo }!
            let binWidth = sampleRate / Double(Self.resolutions[resolution].fftSize)
            return Row(resolution: resolution, lowBin: bottom / binWidth, highBin: top / binWidth, frequency: centre)
        }
    }

    /// One column (0...1 per row) from one spectrum per resolution. Rows narrower than a bin
    /// interpolate between bins, wider rows take their strongest bin (no partial gets lost).
    /// The level mapping keeps the background dark so partials read as bright lines;
    /// +3 dB/octave tilt for treble.
    package func column(from spectra: [[Float]]) -> [Float] {
        rows.map { row in
            let magnitudes = spectra[row.resolution]
            let lastBin = magnitudes.count - 1
            let amplitude: Float
            if row.highBin - row.lowBin < 1 {
                let exact = min(max((row.lowBin + row.highBin) / 2, 0), Double(lastBin - 1))
                let below = Int(exact), fraction = Float(exact - Double(below))
                amplitude = magnitudes[below] * (1 - fraction) + magnitudes[below + 1] * fraction
            } else {
                let first = min(Int(row.lowBin), lastBin), last = min(max(Int(row.highBin), first), lastBin)
                amplitude = magnitudes[first...last].max() ?? 0
            }
            let decibels = 20 * log10(Double(max(amplitude, 1e-10))) + 3 * log2(row.frequency / 1000)
            return Float(max(0, min(1, (decibels + 80) / 66)))
        }
    }
}
