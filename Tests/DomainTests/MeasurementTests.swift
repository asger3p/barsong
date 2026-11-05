@testable import AppDomain
import Foundation
import Testing

private let sampleRate = 48_000.0

private func sine(_ frequency: Double, amplitude: Double, seconds: Double, phase: Double = 0) -> [Float] {
    (0..<Int(sampleRate * seconds)).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate + phase)) }
}

/// Feeds audio in 10 ms chunks, like the audio callback does.
private func feed(_ samples: StereoSamples, to meter: LoudnessMeter) {
    let chunk = 480
    for start in stride(from: 0, to: samples.left.count, by: chunk) {
        let end = min(start + chunk, samples.left.count)
        meter.process(StereoSamples(left: Array(samples.left[start..<end]), right: Array(samples.right[start..<end])), sampleRate: sampleRate)
    }
}

struct LoudnessTests {
    /// The coefficients ITU-R BS.1770 publishes for 48 kHz.
    @Test func kWeightingMatchesTheStandardAt48kHz() {
        let filter = KWeighting(sampleRate: 48_000)
        #expect(abs(filter.shelf.b0 - 1.53512485958697) < 1e-9)
        #expect(abs(filter.shelf.b1 - -2.69169618940638) < 1e-9)
        #expect(abs(filter.shelf.b2 - 1.19839281085285) < 1e-9)
        #expect(abs(filter.shelf.a1 - -1.69065929318241) < 1e-9)
        #expect(abs(filter.shelf.a2 - 0.73248077421585) < 1e-9)
        #expect(abs(filter.highPass.a1 - -1.99004745483398) < 1e-9)
        #expect(abs(filter.highPass.a2 - 0.99007225036621) < 1e-9)
    }

    /// A 1 kHz sine at −20 dBFS in both channels measures −20 LUFS.
    @Test func measuresAReferenceToneCorrectly() throws {
        let meter = LoudnessMeter()
        let tone = sine(1000, amplitude: 0.1, seconds: 5)
        feed(StereoSamples(mono: tone), to: meter)

        let reading = meter.reading
        #expect(abs(try #require(reading.momentary) - -20) < 0.1)
        #expect(abs(try #require(reading.shortTerm) - -20) < 0.1)
        #expect(abs(try #require(reading.integrated) - -20) < 0.1)
        #expect(abs(try #require(reading.peak) - -20) < 0.01)
        #expect(!reading.history.isEmpty)
    }

    @Test func oneChannelIsThreeDecibelsQuieter() throws {
        let meter = LoudnessMeter()
        let tone = sine(1000, amplitude: 0.1, seconds: 4)
        feed(StereoSamples(left: tone, right: [Float](repeating: 0, count: tone.count)), to: meter)
        #expect(abs(try #require(meter.reading.integrated) - -23.01) < 0.1)
    }

    @Test func silenceIsGatedOut() {
        let meter = LoudnessMeter()
        feed(StereoSamples(mono: [Float](repeating: 0, count: Int(sampleRate * 2))), to: meter)
        #expect(meter.reading.momentary == nil)
        #expect(meter.reading.integrated == nil)
    }

    @Test func quietPassagesDontDragTheIntegratedValueDown() throws {
        let meter = LoudnessMeter()
        feed(StereoSamples(mono: sine(1000, amplitude: 0.1, seconds: 5)), to: meter)
        feed(StereoSamples(mono: sine(1000, amplitude: 0.001, seconds: 5)), to: meter) // −60 dBFS: below the relative gate
        #expect(abs(try #require(meter.reading.integrated) - -20) < 0.2)
    }

    @Test func resetStartsOver() {
        let meter = LoudnessMeter()
        feed(StereoSamples(mono: sine(1000, amplitude: 0.1, seconds: 1)), to: meter)
        meter.reset()
        #expect(meter.reading == LoudnessReading())
    }
}

struct LevelMeterTests {
    @Test func fullScaleSineReadsZeroPeakAndMinusThreeRMS() {
        var level = ChannelLevel()
        let tone = sine(1000, amplitude: 1, seconds: 2)
        for start in stride(from: 0, to: tone.count, by: 480) {
            level.update(with: Array(tone[start..<(start + 480)]), duration: 0.01, at: Date())
        }
        #expect(abs(level.peak) < 0.1)
        #expect(abs(level.rms - -3.01) < 0.1)
        #expect(abs(level.hold) < 0.1)
    }

    @Test func peaksFallBackAndTheHoldWaitsBeforeFalling() {
        var level = ChannelLevel()
        let start = Date()
        level.update(with: [1, -1], duration: 0.01, at: start)
        level.update(with: [0, 0], duration: 1, at: start.addingTimeInterval(1))
        #expect(level.peak < -20) // fell 24 dB in a second
        #expect(level.hold == 0) // still held
        level.update(with: [0, 0], duration: 1, at: start.addingTimeInterval(2))
        #expect(level.hold < 0)
    }
}

struct StereoScopeTests {
    @Test func correlationReadsMonoWideAndOutOfPhase() throws {
        let left = sine(440, amplitude: 0.5, seconds: 0.1)
        #expect(abs(try #require(StereoScope.correlation(left, left)) - 1) < 0.001)
        #expect(abs(try #require(StereoScope.correlation(left, left.map { -$0 })) - -1) < 0.001)
        let unrelated = sine(440, amplitude: 0.5, seconds: 0.1, phase: .pi / 2)
        #expect(abs(try #require(StereoScope.correlation(left, unrelated))) < 0.05)
        #expect(StereoScope.correlation([0, 0], [0, 0]) == nil)
    }

    @Test func keepsTheLatestPointsScaledToFit() {
        var scope = StereoScope()
        for _ in 0..<50 {
            scope.update(with: StereoSamples(mono: sine(440, amplitude: 0.05, seconds: 0.01)))
        }
        #expect(scope.left.count == StereoScope.pointCount)
        #expect(scope.left.map(abs).max()! > 0.5) // quiet input is scaled up
        #expect(scope.left == scope.right)
        #expect(scope.correlation > 0.95)
    }
}

struct PitchAndKeyTests {
    @Test func aChordLightsUpItsNotes() {
        let fftSize = 16_384
        let chord = (0..<fftSize).map { index -> Float in
            let time = Double(index) / sampleRate
            return Float([261.63, 329.63, 392.0].reduce(0) { $0 + 0.2 * sin(2 * .pi * $1 * time) }) // C4, E4, G4
        }
        let chroma = PitchClasses.chroma(from: FrequencyAnalyzer(size: fftSize).magnitudes(of: chord), fftSize: fftSize, sampleRate: sampleRate)
        let strongest = Set(chroma.indices.sorted { chroma[$0] > chroma[$1] }.prefix(3))
        #expect(strongest == [0, 4, 7])
    }

    @Test func findsMajorAndMinorKeys() throws {
        // A scale with its tonic and fifth emphasised.
        func profile(tonic: Int, steps: [Int]) -> [Float] {
            var chroma = [Float](repeating: 0.05, count: 12)
            for step in steps { chroma[(tonic + step) % 12] = 0.6 }
            chroma[tonic] = 1
            chroma[(tonic + 7) % 12] = 0.9
            return chroma
        }
        let dMajor = try #require(KeyDetector.key(for: profile(tonic: 2, steps: [0, 2, 4, 5, 7, 9, 11])))
        #expect(dMajor.name == "D major")
        let aMinor = try #require(KeyDetector.key(for: profile(tonic: 9, steps: [0, 2, 3, 5, 7, 8, 10])))
        #expect(aMinor.name == "A minor")
        #expect(aMinor.scale == [9, 11, 0, 2, 4, 5, 7])
        #expect(KeyDetector.key(for: [Float](repeating: 0, count: 12)) == nil)
    }
}

struct WaterfallAndTrackTests {
    @Test func stacksSpectraAndStartsLoudnessOverPerTrack() {
        let analyzer = AudioAnalyzer()
        let tone = sine(1000, amplitude: 0.3, seconds: 0.01)
        var now = Date()
        for _ in 0..<400 {
            analyzer.analyze(tone, sampleRate: sampleRate, at: now)
            now = now.addingTimeInterval(0.01)
        }
        #expect(analyzer.frame.waterfall.count == VisualizerFrame.waterfallDepth)
        #expect(analyzer.frame.waterfall.allSatisfy { $0.count == VisualizerFrame.waterfallSliceLength })
        #expect(analyzer.frame.loudness.integrated != nil)
        #expect(!analyzer.frame.chromaHistory.isEmpty)

        analyzer.startNewTrack()
        #expect(analyzer.frame.loudness.integrated == nil)
        #expect(analyzer.frame.key == nil)
    }
}

struct BalanceTests {
    @Test func centredWhenBothSidesAreEquallyLoud() throws {
        let tone = sine(440, amplitude: 0.5, seconds: 0.1)
        #expect(abs(try #require(StereoScope.balance(tone, tone))) < 0.001)
        #expect(try #require(StereoScope.balance(tone, tone.map { $0 * 0.5 })) < -0.5) // leans left
        #expect(try #require(StereoScope.balance([Float](repeating: 0, count: tone.count), tone)) == 1)
        #expect(StereoScope.balance([0], [0]) == nil)
    }
}
