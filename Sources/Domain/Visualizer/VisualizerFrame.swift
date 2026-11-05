import Foundation

/// The latest analysis of Spotify's audio, ready to draw.
package struct VisualizerFrame: Sendable {
    package static let waveformLength = 256
    /// Points along the analyzer curve, log-spaced over `analyzerRange`.
    package static let analyzerPointCount = 192
    package static let analyzerRange = (low: 20.0, high: 20_000.0)
    /// Slices kept for the wavetable view (about 2 s at 30 a second).
    package static let wavetableDepth = 60
    package static let wavetableSliceLength = 128
    /// Spectra kept for the waterfall (about 2.4 s at 20 a second), each a coarser copy of the analyzer curve.
    package static let waterfallDepth = 48
    package static let waterfallSliceLength = 96
    /// Chroma columns kept for the chromagram (about 8 s at 15 a second).
    package static let chromaHistoryLength = 120

    package var spectrogram = SpectrogramHistory()
    /// -1...1, trigger-aligned like an oscilloscope.
    package var waveform = [Float](repeating: 0, count: waveformLength)
    /// 0...1 per point: a smooth spectrum that rises quickly and falls back gently.
    package var analyzerCurve = [Float](repeating: 0, count: analyzerPointCount)
    /// 0...1 per point: recent peaks, sinking slowly.
    package var analyzerPeaks = [Float](repeating: 0, count: analyzerPointCount)
    /// Recent waveforms for the wavetable view, oldest first, each `wavetableSliceLength` points.
    package var wavetable: [[Float]] = []
    /// Recent spectra for the waterfall, oldest first, each `waterfallSliceLength` points (0...1).
    package var waterfall: [[Float]] = []
    package var stereoScope = StereoScope()
    package var levels = StereoLevels()
    package var loudness = LoudnessReading()
    /// How strongly each note C…B sounds right now, 0...1.
    package var chroma = [Float](repeating: 0, count: 12)
    /// Recent chroma, oldest first.
    package var chromaHistory: [[Float]] = []
    /// The key the music has been in over the last few seconds.
    package var key: MusicalKey?
    /// The tempo over the last few seconds.
    package var tempo: TempoEstimate?
    package var lastSoundAt: Date?

    package init() {}
}

/// Scrolling frequency-over-time image: one byte of intensity (0...255) per pixel, row-major,
/// top row the highest frequency, newest column on the right. At 2× (Retina) that's one
/// pixel per screen pixel; a column every 1/60 s gives about 9 s of history.
package struct SpectrogramHistory: Sendable {
    package static let width = 536
    package static let height = 512

    package private(set) var intensities = [UInt8](repeating: 0, count: width * height)

    package init() {}

    /// Scrolls everything one pixel left and adds a column (0...1 per row, top first) on the right.
    package mutating func append(column: [Float]) {
        let width = Self.width
        intensities.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for (row, value) in column.prefix(Self.height).enumerated() {
                let start = base + row * width
                memmove(start, start + 1, width - 1)
                start[width - 1] = UInt8(max(0, min(1, value)) * 255)
            }
        }
    }
}
