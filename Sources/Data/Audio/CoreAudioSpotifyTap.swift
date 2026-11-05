import AppDomain
import CoreAudio
import Foundation

/// Captures Spotify's audio with a Core Audio process tap (macOS 14.2+): a private,
/// unmuted tap on Spotify's processes, wrapped in a private aggregate device. macOS asks
/// once for "System Audio Recording" permission; only Spotify is tapped.
package final class CoreAudioSpotifyTap: AudioCaptureSource, @unchecked Sendable {
    package enum CaptureError: LocalizedError {
        case unsupportedSystem
        case spotifyNotRunning
        case tapFailed(OSStatus)
        case noOutputDevice
        case aggregateDeviceFailed(OSStatus)
        case startFailed(OSStatus)

        package var errorDescription: String? {
            switch self {
            case .unsupportedSystem: "Needs macOS 14.2 or later"
            case .spotifyNotRunning: "Spotify isn't running"
            case let .tapFailed(status): "Couldn't tap Spotify's audio (error \(status))"
            case .noOutputDevice: "No audio output device"
            case let .aggregateDeviceFailed(status): "Couldn't create the capture device (error \(status))"
            case let .startFailed(status): "Couldn't start capturing (error \(status))"
            }
        }
    }

    private static let deviceName = "Barsong visualizer"
    private static let spotifyBundlePrefix = "com.spotify.client"

    private let queue = DispatchQueue(label: "dev.asger.Barsong.audio", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    package init() {}

    package func start(onSamples: @escaping @Sendable (StereoSamples, Double) -> Void) throws {
        guard #available(macOS 14.2, *) else { throw CaptureError.unsupportedSystem }
        let processes = Self.spotifyAudioProcesses()
        guard !processes.isEmpty else { throw CaptureError.spotifyNotRunning }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = Self.deviceName

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw CaptureError.tapFailed(status) }
        tapID = tap
        let sampleRate = Self.tapSampleRate(tap) ?? 48_000

        guard let outputUID = Self.defaultOutputDeviceUID() else { throw CaptureError.noOutputDevice }
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.deviceName,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard status == noErr else { throw CaptureError.aggregateDeviceFailed(status) }
        aggregateID = aggregate

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregate, queue) { _, input, _, _, _ in
            if let samples = Self.stereoSamples(from: input) { onSamples(samples, sampleRate) }
        }
        if status == noErr { status = AudioDeviceStart(aggregate, ioProcID) }
        guard status == noErr else { throw CaptureError.startFailed(status) }
    }

    package func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: Samples

    /// Left and right from one buffer per channel or from interleaved audio. Mono audio is
    /// used for both sides.
    private static func stereoSamples(from input: UnsafePointer<AudioBufferList>) -> StereoSamples? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let firstData = first.mData, first.mDataByteSize > 0 else { return nil }
        let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let firstSamples = UnsafeBufferPointer(start: firstData.assumingMemoryBound(to: Float.self), count: floatCount)
        if buffers.count >= 2, let secondData = buffers[1].mData {
            let secondSamples = UnsafeBufferPointer(start: secondData.assumingMemoryBound(to: Float.self), count: floatCount)
            return StereoSamples(left: Array(firstSamples), right: Array(secondSamples))
        }
        let channels = max(Int(first.mNumberChannels), 1)
        guard channels > 1 else { return StereoSamples(mono: Array(firstSamples)) }
        let frames = floatCount / channels
        let left = (0..<frames).map { firstSamples[$0 * channels] }
        let right = (0..<frames).map { firstSamples[$0 * channels + 1] }
        return StereoSamples(left: left, right: right)
    }

    // MARK: Core Audio lookups

    /// Spotify and its helper processes (whichever one is producing the sound).
    @available(macOS 14.2, *)
    private static func spotifyAudioProcesses() -> [AudioObjectID] {
        var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { stringProperty(kAudioProcessPropertyBundleID, of: $0)?.hasPrefix(spotifyBundlePrefix) == true }
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        return stringProperty(kAudioDevicePropertyDeviceUID, of: device)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    @available(macOS 14.2, *)
    private static func tapSampleRate(_ tap: AudioObjectID) -> Double? {
        var address = globalAddress(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 else { return nil }
        return format.mSampleRate
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
