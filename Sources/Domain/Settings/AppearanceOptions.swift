import Foundation

/// What the menu bar item writes next to the cover.
package enum MenuBarTextStyle: String, CaseIterable, Identifiable, Sendable {
    case artistTitle, titleArtist, titleOnly, hidden

    package var id: String { rawValue }

    /// The text for a track, shortened with "…" past `maxLength` characters. Nil for `hidden`.
    package func text(for track: Track, maxLength: Int) -> String? {
        let text: String
        switch self {
        case .artistTitle: text = "\(track.artist) – \(track.title)"
        case .titleArtist: text = "\(track.title) – \(track.artist)"
        case .titleOnly: text = track.title
        case .hidden: return nil
        }
        return text.count > maxLength ? String(text.prefix(max(maxLength - 1, 0))) + "…" : text
    }
}

/// Background behind the menu bar item.
package enum MenuBarBackground: String, CaseIterable, Identifiable, Sendable {
    case none, pill, album

    package var id: String { rawValue }
}

/// The visuals the visualizer column can show; clicking it moves to the next one.
package enum VisualizerStyle: String, CaseIterable, Identifiable, Sendable {
    case analyzer, spectrogram, waterfall, oscilloscope, wavetable, vectorscope, meters, loudness, chromagram

    package var id: String { rawValue }

    /// Reads a saved value, including names from earlier versions. Retired visuals give nil.
    package init?(storedValue: String) {
        switch storedValue {
        case "waveLine": self = .oscilloscope
        default: self.init(rawValue: storedValue)
        }
    }

    package var next: VisualizerStyle { stepped(by: 1) }
    package var previous: VisualizerStyle { stepped(by: -1) }

    /// Wraps around at either end.
    private func stepped(by offset: Int) -> VisualizerStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + offset + all.count) % all.count]
    }
}
