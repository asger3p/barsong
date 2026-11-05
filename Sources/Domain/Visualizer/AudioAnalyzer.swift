import Accelerate
import Foundation

/// Turns a stream of stereo samples into a `VisualizerFrame`: spectrum curve, spectrogram,
/// waveform, wavetable and waterfall stacks, stereo scope, level and loudness meters, and the
/// notes being played, the key and the tempo.
/// Not thread-safe: feed it from one queue.
package final class AudioAnalyzer {
    /// Spectrum curve and waves: about 11 Hz per bin at 48 kHz, quick to react.
    private static let shortWindow = 4096
    private static let spectrogramColumnInterval: TimeInterval = 1.0 / 60
    private static let wavetableSliceInterval: TimeInterval = 1.0 / 30
    private static let waterfallSliceInterval: TimeInterval = 1.0 / 20
    private static let chromaColumnInterval: TimeInterval = 1.0 / 15
    private static let waveformSmoothingWidth = 7
    /// RMS below this counts as silence.
    private static let silenceThreshold: Float = 0.0005
    /// How much each new chroma reading moves the key estimate (about 15 s of memory at 60 a second).
    private static let keyMemory: Float = 0.999

    package private(set) var frame = VisualizerFrame()

    private var recentSamples: [Float] = []
    private let shortAnalyzer = FrequencyAnalyzer(size: shortWindow)
    private let spectrogramAnalyzers = SpectrogramLayout.resolutions.map { FrequencyAnalyzer(size: $0.fftSize) }
    private var spectrogramLayout: SpectrogramLayout?
    private let loudnessMeter = LoudnessMeter()
    private let tempoDetector = TempoDetector()
    private var onsetStrength = OnsetStrength()
    private var keyChroma = [Float](repeating: 0, count: 12)
    private var lastSpectrogramColumn = Date.distantPast
    private var lastWavetableSlice = Date.distantPast
    private var lastWaterfallSlice = Date.distantPast
    private var lastChromaColumn = Date.distantPast
    private var waveformGain: Float = 1
    /// After a pause: ignore the silence before the music comes back.
    private var isWaitingForSound = false

    package init() {}

    /// Carries on from a held frame after a pause. Old samples are dropped and silence is
    /// skipped until the music is back, so nothing flat or stale gets drawn in between.
    package func resume(from held: VisualizerFrame) {
        frame = held
        recentSamples = []
        isWaitingForSound = true
    }

    /// Starts the loudness measurement and key estimate afresh (a new track).
    package func startNewTrack() {
        loudnessMeter.reset()
        frame.loudness = loudnessMeter.reading
        tempoDetector.reset()
        frame.tempo = nil
        keyChroma = [Float](repeating: 0, count: 12)
        frame.key = nil
    }

    /// Mono convenience: the same signal in both channels.
    package func analyze(_ mono: [Float], sampleRate: Double, at now: Date = Date()) {
        analyze(StereoSamples(mono: mono), sampleRate: sampleRate, at: now)
    }

    package func analyze(_ samples: StereoSamples, sampleRate: Double, at now: Date = Date()) {
        let chunk = samples.mono
        guard !chunk.isEmpty else { return }
        let rms = vDSP.rootMeanSquare(chunk)
        if isWaitingForSound {
            guard rms > Self.silenceThreshold else { return }
            isWaitingForSound = false
        }

        // Meters work on every chunk, from the first sample.
        let duration = Double(chunk.count) / sampleRate
        frame.levels.left.update(with: samples.left, duration: duration, at: now)
        frame.levels.right.update(with: samples.right, duration: duration, at: now)
        frame.stereoScope.update(with: samples)
        loudnessMeter.process(samples, sampleRate: sampleRate)
        frame.loudness = loudnessMeter.reading
        if rms > Self.silenceThreshold { frame.lastSoundAt = now }

        let keep = SpectrogramLayout.longestWindow
        recentSamples.append(contentsOf: chunk)
        if recentSamples.count > keep { recentSamples.removeFirst(recentSamples.count - keep) }
        guard recentSamples.count >= Self.shortWindow else { return }
        let latest = Array(recentSamples.suffix(Self.shortWindow))

        let magnitudes = shortAnalyzer.magnitudes(of: latest)
        tempoDetector.add(onsetStrength: onsetStrength.next(from: magnitudes), duration: duration)
        frame.tempo = tempoDetector.tempo
        updateAnalyzerCurve(towards: SpectrumBands.logBands(
            magnitudes, count: VisualizerFrame.analyzerPointCount, sampleRate: sampleRate,
            low: VisualizerFrame.analyzerRange.low, high: VisualizerFrame.analyzerRange.high
        ))
        addWaterfallSlice(now: now)


        // Blend with the previous frame: the shape glides instead of flickering.
        frame.waveform = vDSP.add(vDSP.multiply(0.8, frame.waveform), vDSP.multiply(0.2, steadyWaveform(from: latest)))
        addWavetableSlice(now: now)

        updateLongWindowViews(sampleRate: sampleRate, now: now)
    }

    // MARK: Long windows: spectrogram and notes

    /// 60 times a second, once there are enough samples for the longest window: a spectrogram
    /// column, and from the finest (bass-accurate) spectrum the notes being played.
    private func updateLongWindowViews(sampleRate: Double, now: Date) {
        guard recentSamples.count == SpectrogramLayout.longestWindow,
              now.timeIntervalSince(lastSpectrogramColumn) >= Self.spectrogramColumnInterval
        else { return }
        lastSpectrogramColumn = now
        if spectrogramLayout?.sampleRate != sampleRate {
            spectrogramLayout = SpectrogramLayout(sampleRate: sampleRate)
        }
        let spectra = spectrogramAnalyzers.map { $0.magnitudes(of: recentSamples) }
        if let column = spectrogramLayout?.column(from: spectra) {
            frame.spectrogram.append(column: column)
        }
        updateNotes(from: spectra[0], fftSize: SpectrogramLayout.resolutions[0].fftSize, sampleRate: sampleRate, now: now)
    }

    private func updateNotes(from magnitudes: [Float], fftSize: Int, sampleRate: Double, now: Date) {
        let chroma = PitchClasses.chroma(from: magnitudes, fftSize: fftSize, sampleRate: sampleRate)
        frame.chroma = vDSP.add(vDSP.multiply(0.8, frame.chroma), vDSP.multiply(0.2, chroma))
        keyChroma = vDSP.add(vDSP.multiply(Self.keyMemory, keyChroma), vDSP.multiply(1 - Self.keyMemory, chroma))
        frame.key = KeyDetector.key(for: keyChroma)

        guard now.timeIntervalSince(lastChromaColumn) >= Self.chromaColumnInterval else { return }
        lastChromaColumn = now
        frame.chromaHistory.append(frame.chroma)
        if frame.chromaHistory.count > VisualizerFrame.chromaHistoryLength {
            frame.chromaHistory.removeFirst(frame.chromaHistory.count - VisualizerFrame.chromaHistoryLength)
        }
    }

    // MARK: Stacks

    /// The current (steady) waveform as the newest wavetable slice, 30 times a second.
    private func addWavetableSlice(now: Date) {
        guard now.timeIntervalSince(lastWavetableSlice) >= Self.wavetableSliceInterval else { return }
        lastWavetableSlice = now
        Self.push(Self.downsampled(frame.waveform, to: VisualizerFrame.wavetableSliceLength),
                  onto: &frame.wavetable, keeping: VisualizerFrame.wavetableDepth)
    }

    /// The current analyzer curve as the newest waterfall slice, 20 times a second.
    private func addWaterfallSlice(now: Date) {
        guard now.timeIntervalSince(lastWaterfallSlice) >= Self.waterfallSliceInterval else { return }
        lastWaterfallSlice = now
        Self.push(Self.downsampled(frame.analyzerCurve, to: VisualizerFrame.waterfallSliceLength),
                  onto: &frame.waterfall, keeping: VisualizerFrame.waterfallDepth)
    }

    /// Averages neighbouring points down to `length` (an exact divisor of the input).
    private static func downsampled(_ points: [Float], to length: Int) -> [Float] {
        let group = points.count / length
        return (0..<length).map { index in
            let start = index * group
            return points[start..<(start + group)].reduce(0, +) / Float(group)
        }
    }

    private static func push(_ slice: [Float], onto stack: inout [[Float]], keeping depth: Int) {
        stack.append(slice)
        if stack.count > depth { stack.removeFirst(stack.count - depth) }
    }

    // MARK: Shapes and spectra

    /// Trigger-aligned, averaged down to 256 points, and scaled by a gain that eases
    /// instead of jumping with every peak.
    private func steadyWaveform(from samples: [Float]) -> [Float] {
        let stable = Waveform.stable(from: samples, length: VisualizerFrame.waveformLength)
        let peak = max(vDSP.maximumMagnitude(stable), 0.15)
        waveformGain = 1 / peak < waveformGain ? 1 / peak : waveformGain * 0.985 + (1 / peak) * 0.015
        return Waveform.evenedOut(vDSP.multiply(waveformGain, stable), width: Self.waveformSmoothingWidth)
    }

    /// The curve follows rises closely and falls back gently; peaks hold, then sink slowly.
    private func updateAnalyzerCurve(towards targets: [Float]) {
        for index in targets.indices {
            let target = targets[index], current = frame.analyzerCurve[index]
            let curve = target > current ? current * 0.4 + target * 0.6 : current * 0.88 + target * 0.12
            frame.analyzerCurve[index] = curve
            frame.analyzerPeaks[index] = max(curve, frame.analyzerPeaks[index] - 0.003)
        }
    }
}
