@testable import AppDomain
import Foundation
import Testing

struct TempoTests {
    /// An onset-strength signal with a sharp spike on every beat (and a little noise).
    private func clickTrack(bpm: Double, seconds: Double = 8) -> [Float] {
        let rate = TempoDetector.envelopeRate
        let interval = 60 / bpm * rate
        return (0..<Int(seconds * rate)).map { slot in
            let phase = Double(slot).truncatingRemainder(dividingBy: interval)
            return (phase < 1 ? 1 : 0) + Float.random(in: 0...0.05)
        }
    }

    @Test(arguments: [90.0, 120.0, 128.0, 174.0])
    func findsTheTempoOfAClickTrack(bpm: Double) throws {
        let estimate = try #require(TempoDetector.estimate(envelope: clickTrack(bpm: bpm), rate: TempoDetector.envelopeRate))
        #expect(abs(estimate.bpm - bpm) < 1.5)
        #expect(estimate.confidence > 0.3)
    }

    @Test func silenceHasNoTempo() {
        #expect(TempoDetector.estimate(envelope: [Float](repeating: 0, count: 800), rate: 100) == nil)
    }

    @Test func steadiesAndResets() throws {
        let detector = TempoDetector()
        for value in clickTrack(bpm: 128, seconds: 10) {
            detector.add(onsetStrength: value, duration: 0.01)
        }
        #expect(abs(try #require(detector.tempo).bpm - 128) < 1.5)
        detector.reset()
        #expect(detector.tempo == nil)
    }

    @Test func onsetStrengthRisesOnAttacksOnly() {
        var onset = OnsetStrength()
        _ = onset.next(from: [0, 0, 0])
        #expect(onset.next(from: [1, 1, 1]) > 0)
        #expect(onset.next(from: [0, 0, 0]) == 0) // falling doesn't count
    }

    @Test func theAnalyzerHearsAKickDrumBeat() throws {
        let analyzer = AudioAnalyzer()
        let rate = 48_000.0, bpm = 124.0
        var sampleIndex = 0, now = Date()
        for _ in 0..<1000 { // 10 s in 10 ms chunks
            let chunk = (0..<480).map { _ -> Float in
                let t = Double(sampleIndex) / rate
                sampleIndex += 1
                let sinceBeat = t.truncatingRemainder(dividingBy: 60 / bpm)
                return Float(0.6 * exp(-sinceBeat * 25) * sin(2 * .pi * 60 * sinceBeat) + 0.05 * sin(2 * .pi * 440 * t))
            }
            analyzer.analyze(chunk, sampleRate: rate, at: now)
            now = now.addingTimeInterval(0.01)
        }
        #expect(abs(try #require(analyzer.frame.tempo).bpm - bpm) < 2)
    }
}
