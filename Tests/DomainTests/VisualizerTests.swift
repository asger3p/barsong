@testable import AppDomain
import Foundation
import Testing

struct SpectrumTests {
    private let sampleRate = 48_000.0

    private func tone(_ frequency: Double, count: Int = 4096) -> [Float] {
        (0..<count).map { Float(0.5 * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// The band (of 32 between 40 Hz and 16 kHz) a frequency falls in.
    private func expectedBand(_ frequency: Double) -> Int {
        Int(Double(32) * log(frequency / 40) / log(16_000.0 / 40))
    }

    @Test(arguments: [100.0, 1000.0, 8000.0])
    func toneLightsUpItsOwnBand(frequency: Double) {
        let magnitudes = FrequencyAnalyzer(size: 4096).magnitudes(of: tone(frequency))
        let bands = SpectrumBands.logBands(magnitudes, count: 32, sampleRate: sampleRate, low: 40, high: 16_000)
        let loudest = bands.indices.max { bands[$0] < bands[$1] }!
        #expect(abs(loudest - expectedBand(frequency)) <= 1)
    }

    @Test func silenceStaysDark() {
        let magnitudes = FrequencyAnalyzer(size: 4096).magnitudes(of: [Float](repeating: 0, count: 4096))
        let bands = SpectrumBands.logBands(magnitudes, count: 32, sampleRate: sampleRate, low: 40, high: 16_000)
        #expect(bands.allSatisfy { $0 == 0 })
    }
}

struct WaveformTests {
    @Test func aSteadyToneDrawsInTheSamePlace() {
        let sampleRate = 48_000.0
        let signal = (0..<8192).map { Float(sin(2 * .pi * 220 * Double($0) / sampleRate)) }
        // Two windows that end at different points in the cycle.
        let first = Waveform.stable(from: Array(signal[0..<4096]), length: 256)
        let second = Waveform.stable(from: Array(signal[37..<(37 + 4096)]), length: 256)
        let difference = zip(first, second).map { abs($0 - $1) }.max()!
        #expect(difference < 0.1)
    }

    @Test func tooFewSamplesGiveAFlatLine() {
        #expect(Waveform.stable(from: [1, 2, 3], length: 256) == [Float](repeating: 0, count: 256))
    }

    @Test func evensOutSpikesButKeepsTheEdges() {
        let points: [Float] = [0, 0, 0, 7, 0, 0, 0]
        let evened = Waveform.evenedOut(points, width: 3)
        #expect(evened[3] < 7)
        #expect(evened.first == 0)
        #expect(evened.count == points.count)
    }
}

struct SpectrogramTests {
    private let layout = SpectrogramLayout(sampleRate: 48_000)

    @Test func rowsRunFromTrebleDownToBass() {
        #expect(layout.rows.count == SpectrogramHistory.height)
        let frequencies = layout.rows.map(\.frequency)
        #expect(zip(frequencies, frequencies.dropFirst()).allSatisfy { $0 > $1 })
        #expect(frequencies.first! < 16_000 && frequencies.last! > 30)
    }

    @Test func bassUsesTheLongestWindow() {
        #expect(layout.rows.last?.resolution == 0)
        #expect(layout.rows.first?.resolution == SpectrogramLayout.resolutions.count - 1)
    }

    @Test func newColumnsAppearOnTheRight() {
        var history = SpectrogramHistory()
        history.append(column: [Float](repeating: 1, count: SpectrogramHistory.height))
        history.append(column: [Float](repeating: 0.5, count: SpectrogramHistory.height))
        let width = SpectrogramHistory.width
        #expect(history.intensities[width - 1] == 127)
        #expect(history.intensities[width - 2] == 255)
        #expect(history.intensities[width - 3] == 0)
    }
}

struct AudioAnalyzerTests {
    @Test func aLoudToneShowsOnTheMetersAndMarksSound() {
        let analyzer = AudioAnalyzer()
        let sampleRate = 48_000.0
        let chunk = (0..<512).map { Float(0.8 * sin(2 * .pi * 440 * Double($0) / sampleRate)) }
        for _ in 0..<40 { analyzer.analyze(chunk, sampleRate: sampleRate) }
        #expect(analyzer.frame.levels.left.peak > -3)
        #expect(analyzer.frame.lastSoundAt != nil)
    }
}

final class FakeAudioSource: AudioCaptureSource {
    var startError: Error?
    private(set) var isRunning = false
    private var onSamples: ((StereoSamples, Double) -> Void)?

    func start(onSamples: @escaping @Sendable (StereoSamples, Double) -> Void) throws {
        if let startError { throw startError }
        isRunning = true
        self.onSamples = onSamples
    }

    /// Delivers audio as if Spotify were playing it.
    func play(_ samples: [Float], sampleRate: Double = 48_000) {
        onSamples?(StereoSamples(mono: samples), sampleRate)
    }

    func stop() { isRunning = false }
}

struct LiveAudioVisualizerTests {
    private let tone = (0..<4096).map { Float(0.6 * sin(2 * .pi * 440 * Double($0) / 48_000)) }
    private let silence = [Float](repeating: 0, count: 4096)

    @Test func reportsWhyCapturingFailed() {
        let source = FakeAudioSource()
        source.startError = TestFailure()
        let visualizer = LiveAudioVisualizer(source: source)

        visualizer.start()

        #expect(visualizer.status == .failed("Something went wrong"))
        #expect(visualizer.issue(isPlaying: true, now: Date()) == .captureFailed("Something went wrong"))
    }

    @Test func suspectsMissingPermissionWhenPlayingInSilence() {
        let visualizer = LiveAudioVisualizer(source: FakeAudioSource())
        visualizer.start()

        #expect(visualizer.issue(isPlaying: true, now: Date()) == nil) // give it a moment
        #expect(visualizer.issue(isPlaying: true, now: Date().addingTimeInterval(10)) == .noSound)
        #expect(visualizer.issue(isPlaying: false, now: Date().addingTimeInterval(10)) == nil)
    }

    @Test func holdsThePictureFromTheLastSound() {
        let source = FakeAudioSource()
        let visualizer = LiveAudioVisualizer(source: source)
        visualizer.start()
        let tone = (0..<4096).map { Float(0.6 * sin(2 * .pi * 440 * Double($0) / 48_000)) }

        source.play(tone)
        let whilePlaying = visualizer.lastAudibleSnapshot()
        source.play([Float](repeating: 0, count: 4096))
        source.play([Float](repeating: 0, count: 4096))

        #expect(visualizer.lastAudibleSnapshot().analyzerCurve == whilePlaying.analyzerCurve)
        #expect(visualizer.snapshot().analyzerCurve != whilePlaying.analyzerCurve) // the live frame kept falling
    }

    @Test func pausingStopsListeningAndHoldsThePicture() {
        let source = FakeAudioSource()
        let visualizer = LiveAudioVisualizer(source: source)
        visualizer.start()
        source.play(tone)
        let held = visualizer.lastAudibleSnapshot()
        source.play(silence) // the moment between pressing pause and Spotify going quiet

        visualizer.pause()

        #expect(visualizer.status == .paused)
        #expect(!source.isRunning)
        #expect(visualizer.snapshot().analyzerCurve == held.analyzerCurve)
        #expect(visualizer.issue(isPlaying: false, now: Date().addingTimeInterval(10)) == nil)
    }

    @Test func resumingSkipsSilenceAndCarriesOn() {
        let source = FakeAudioSource()
        let visualizer = LiveAudioVisualizer(source: source)
        visualizer.start()
        source.play(tone)
        visualizer.pause()
        let held = visualizer.snapshot()

        visualizer.start()
        source.play(silence) // before the music is back
        #expect(visualizer.status == .running)
        #expect(visualizer.snapshot().wavetable == held.wavetable)

        source.play(tone)
        #expect(visualizer.snapshot().lastSoundAt != held.lastSoundAt)
    }

    @Test func stoppingClearsTheStatus() {
        let source = FakeAudioSource()
        let visualizer = LiveAudioVisualizer(source: source)
        visualizer.start()
        visualizer.stop()

        #expect(visualizer.status == .stopped)
        #expect(!source.isRunning)
    }
}

struct WavetableTests {
    @Test func keepsARollingStackOfSlices() {
        let analyzer = AudioAnalyzer()
        let sampleRate = 48_000.0
        let chunk = (0..<4096).map { Float(sin(2 * .pi * 220 * Double($0) / sampleRate)) }
        var now = Date()
        for _ in 0..<300 {
            analyzer.analyze(chunk, sampleRate: sampleRate, at: now)
            now = now.addingTimeInterval(1.0 / 100)
        }
        #expect(analyzer.frame.wavetable.count == VisualizerFrame.wavetableDepth)
        #expect(analyzer.frame.wavetable.allSatisfy { $0.count == VisualizerFrame.wavetableSliceLength })
        #expect(analyzer.frame.wavetable.last!.contains { abs($0) > 0.1 })
    }
}

struct AnalyzerCurveTests {
    @Test func aToneRaisesTheCurveAtItsFrequencyAndHoldsThePeak() {
        let analyzer = AudioAnalyzer()
        let sampleRate = 48_000.0
        let chunk = (0..<4096).map { Float(0.5 * sin(2 * .pi * 1000 * Double($0) / sampleRate)) }
        for _ in 0..<10 { analyzer.analyze(chunk, sampleRate: sampleRate) }

        let curve = analyzer.frame.analyzerCurve
        let loudest = curve.indices.max { curve[$0] < curve[$1] }!
        let range = VisualizerFrame.analyzerRange
        let expected = Int(Double(VisualizerFrame.analyzerPointCount) * log(1000 / range.low) / log(range.high / range.low))
        #expect(abs(loudest - expected) <= 2)
        #expect(zip(analyzer.frame.analyzerPeaks, curve).allSatisfy { $0 >= $1 })

        for _ in 0..<10 { analyzer.analyze([Float](repeating: 0, count: 4096), sampleRate: sampleRate) }
        #expect(analyzer.frame.analyzerCurve[loudest] < curve[loudest])
        #expect(analyzer.frame.analyzerPeaks[loudest] > analyzer.frame.analyzerCurve[loudest])
    }
}
