import Foundation

/// Delivers the audio coming out of Spotify, left and right.
package protocol AudioCaptureSource: AnyObject {
    /// Starts calling `onSamples` (on a background queue) with each chunk and its sample rate.
    /// Throws a `LocalizedError` saying what went wrong.
    func start(onSamples: @escaping @Sendable (_ samples: StereoSamples, _ sampleRate: Double) -> Void) throws
    func stop()
}

/// Runs the analysis of Spotify's audio while the visualizer is on screen, and hands
/// out the latest frame to draw. Safe to read from any thread.
package final class LiveAudioVisualizer: @unchecked Sendable {
    package enum Status: Equatable, Sendable {
        case stopped, running
        /// Not listening (Spotify is paused), holding the last picture.
        case paused
        case failed(String)
    }

    /// Why the visualizer has nothing to show.
    package enum Issue: Equatable, Sendable {
        case captureFailed(String)
        /// Playing, but only silence comes through: most likely the audio recording permission is missing.
        case noSound
    }

    /// How long playback may stay silent before that counts as a problem.
    private static let silenceGracePeriod: TimeInterval = 3

    private let source: AudioCaptureSource
    private let frameLock = NSLock()
    private let analysisLock = NSLock()
    private var frame = VisualizerFrame()
    /// The frame as it was at the last moment there was sound, so pausing can freeze the picture
    /// as it was while playing, without the silence after it.
    private var lastAudibleFrame = VisualizerFrame()
    private var currentStatus: Status = .stopped
    private var startedAt: Date?
    private var analyzer = AudioAnalyzer()

    package init(source: AudioCaptureSource) {
        self.source = source
    }

    package var status: Status {
        frameLock.withLock { currentStatus }
    }

    package func snapshot() -> VisualizerFrame {
        frameLock.withLock { frame }
    }

    /// The picture to hold while paused.
    package func lastAudibleSnapshot() -> VisualizerFrame {
        frameLock.withLock { lastAudibleFrame }
    }

    /// Starts listening, or after a pause carries on from the held picture.
    package func start() {
        let previous = status
        guard previous != .running else { return }
        if previous == .paused {
            let held = lastAudibleSnapshot()
            analysisLock.withLock { analyzer.resume(from: held) }
        }
        do {
            try source.start { [weak self] samples, sampleRate in
                self?.analyze(samples, sampleRate: sampleRate)
            }
            frameLock.withLock {
                startedAt = Date()
                currentStatus = .running
            }
        } catch {
            source.stop()
            frameLock.withLock { currentStatus = .failed(error.localizedDescription) }
        }
    }

    /// Stops listening but keeps the picture as it was at the last sound, so it can be studied
    /// and `start()` can carry on from it.
    package func pause() {
        guard status == .running else { return }
        source.stop()
        frameLock.withLock {
            frame = lastAudibleFrame
            currentStatus = .paused
        }
    }

    package func stop() {
        source.stop()
        analysisLock.withLock { analyzer = AudioAnalyzer() }
        frameLock.withLock {
            frame = VisualizerFrame()
            lastAudibleFrame = VisualizerFrame()
            startedAt = nil
            currentStatus = .stopped
        }
    }

    package func issue(isPlaying: Bool, now: Date) -> Issue? {
        let (status, startedAt, lastSoundAt) = frameLock.withLock { (currentStatus, self.startedAt, frame.lastSoundAt) }
        switch status {
        case let .failed(reason):
            return .captureFailed(reason)
        case .running:
            guard isPlaying, let startedAt, now.timeIntervalSince(startedAt) > Self.silenceGracePeriod else { return nil }
            let silentFor = now.timeIntervalSince(lastSoundAt ?? startedAt)
            return silentFor > Self.silenceGracePeriod ? .noSound : nil
        case .stopped, .paused:
            return nil
        }
    }

    /// A new track: the loudness measurement and key estimate start over.
    package func startNewTrack() {
        let reset = analysisLock.withLock {
            analyzer.startNewTrack()
            return analyzer.frame
        }
        frameLock.withLock {
            frame.loudness = reset.loudness
            frame.key = nil
            frame.tempo = nil
            lastAudibleFrame.loudness = reset.loudness
            lastAudibleFrame.key = nil
            lastAudibleFrame.tempo = nil
        }
    }

    private func analyze(_ samples: StereoSamples, sampleRate: Double) {
        let (analyzed, wasAudible) = analysisLock.withLock {
            let soundBefore = analyzer.frame.lastSoundAt
            analyzer.analyze(samples, sampleRate: sampleRate)
            return (analyzer.frame, analyzer.frame.lastSoundAt != soundBefore)
        }
        frameLock.withLock {
            guard currentStatus == .running else { return }
            frame = analyzed
            if wasAudible { lastAudibleFrame = analyzed }
        }
    }
}
