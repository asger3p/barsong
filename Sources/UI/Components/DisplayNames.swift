import AppDomain
import SwiftUI

// What the domain's options are called on screen.

extension MenuBarTextStyle {
    var label: String {
        switch self {
        case .artistTitle: "Artist – Title"
        case .titleArtist: "Title – Artist"
        case .titleOnly: "Title only"
        case .hidden: "None (icons only)"
        }
    }
}

extension MenuBarBackground {
    var label: String {
        switch self {
        case .none: "None"
        case .pill: "Pill"
        case .album: "Album-coloured pill"
        }
    }
}

extension VisualizerStyle {
    var label: String {
        switch self {
        case .analyzer: "Spectrum analyzer"
        case .spectrogram: "Spectrogram"
        case .waterfall: "Spectral waterfall"
        case .oscilloscope: "Oscilloscope"
        case .wavetable: "Wavetable"
        case .vectorscope: "Vectorscope"
        case .meters: "Level meters"
        case .loudness: "Loudness (LUFS)"
        case .chromagram: "Chromagram"
        }
    }
}

extension LyricsDefaultPosition {
    var label: String {
        switch self {
        case .topCenter: "Below menu bar"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .center: "Centre of screen"
        }
    }

    /// How the pill sits inside its (wider) window.
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .topLeft: .leading
        case .topRight: .trailing
        case .topCenter, .center: .center
        }
    }
}

extension LyricsPillStyle {
    var label: String { rawValue.capitalized }

    var textColor: Color {
        switch self {
        case .dark, .album: .white
        case .light: .black
        case .glass: .primary // follows light/dark mode, readable on the glass tint
        }
    }
}

extension LyricsSession {
    var statusText: String {
        switch status {
        case .off: ""
        case .loading: "Looking for lyrics…"
        case .synced: "Synced lyrics" + (source.map { " · \($0)" } ?? "")
        case .unsynced: "Only unsynced lyrics found"
        case .notFound: "No lyrics found"
        case .notASong: "No lyrics for this item"
        }
    }

    /// Shown briefly in the pill when the song has no usable lyrics.
    var unavailableNotice: String? {
        guard isShowingUnavailableNotice else { return nil }
        switch status {
        case .unsynced: return "Lyrics for this song aren't synced"
        case .notASong: return "No lyrics for this item"
        default: return "No lyrics for this song"
        }
    }
}

enum LyricsLineCount {
    static func description(_ count: Int) -> String {
        switch count {
        case 2: "Current and next"
        case 3: "Previous, current and next"
        case 5: "Two before and after"
        default: "Current line only"
        }
    }
}

enum PlaybackTimeFormat {
    /// "3:07".
    static func string(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
