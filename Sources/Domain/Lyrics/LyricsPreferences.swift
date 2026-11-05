import Combine
import Foundation

/// Where the lyrics go by default (and when reset).
package enum LyricsDefaultPosition: String, CaseIterable, Identifiable, Sendable {
    case topCenter, topLeft, topRight, center

    package var id: String { rawValue }
}

package enum LyricsPillStyle: String, CaseIterable, Identifiable, Sendable {
    case dark, light, glass, album

    package var id: String { rawValue }
}

/// How the floating lyrics look and where they sit, kept between launches.
@MainActor
package final class LyricsPreferences: ObservableObject {
    private enum Key {
        static let timingOffset = "lyricsTimingOffset"
        static let visibleLineCount = "lyricsVisibleLineCount"
        static let pillStyle = "lyricsPillStyle"
        static let expanded = "lyricsExpanded"
        static let defaultPosition = "lyricsDefaultPosition"
        static let windowAnchor = "lyricsWindowAnchor"
    }

    package static let defaultTimingOffset: TimeInterval = 0.2
    package static let timingOffsetRange: ClosedRange<Double> = -3...3

    /// Seconds to show each line early (positive) or late (negative). Slightly early by
    /// default, so each line lands with the vocal rather than after it.
    @Published package var timingOffset: TimeInterval {
        didSet { storage.set(timingOffset, forKey: Key.timingOffset) }
    }
    /// One of `LyricsTimeline.lineCountOptions`.
    @Published package var visibleLineCount: Int {
        didSet { storage.set(visibleLineCount, forKey: Key.visibleLineCount) }
    }
    @Published package var pillStyle: LyricsPillStyle {
        didSet { storage.set(pillStyle.rawValue, forKey: Key.pillStyle) }
    }
    /// Large full-height view of the whole song instead of the small pill.
    @Published package var isExpanded: Bool {
        didSet { storage.set(isExpanded, forKey: Key.expanded) }
    }
    /// Choosing a default also moves the lyrics there.
    @Published package var defaultPosition: LyricsDefaultPosition {
        didSet {
            storage.set(defaultPosition.rawValue, forKey: Key.defaultPosition)
            positionResetRequests.send()
        }
    }

    /// Asks the lyrics window to go back to the default position.
    package let positionResetRequests = PassthroughSubject<Void, Never>()

    private let storage: SettingsStorage

    package init(storage: SettingsStorage) {
        self.storage = storage
        timingOffset = storage.value(forKey: Key.timingOffset) ?? Self.defaultTimingOffset
        let savedLineCount: Int = storage.value(forKey: Key.visibleLineCount) ?? 1
        visibleLineCount = LyricsTimeline.lineCountOptions.contains(savedLineCount) ? savedLineCount : 1
        pillStyle = storage.value(forKey: Key.pillStyle).flatMap(LyricsPillStyle.init) ?? .dark
        isExpanded = storage.value(forKey: Key.expanded) ?? false
        defaultPosition = storage.value(forKey: Key.defaultPosition).flatMap(LyricsDefaultPosition.init) ?? .topCenter
    }

    /// Top centre of the lyrics window in screen coordinates, if it was dragged somewhere.
    package var windowAnchor: CGPoint? {
        get { storage.value(forKey: Key.windowAnchor).map { (saved: String) in NSPointFromString(saved) } }
        set { storage.set(newValue.map { NSStringFromPoint($0) }, forKey: Key.windowAnchor) }
    }

    /// Forgets the dragged position and moves the lyrics back to the default one.
    package func resetPosition() {
        windowAnchor = nil
        positionResetRequests.send()
    }
}
