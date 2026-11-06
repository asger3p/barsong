import AppDomain
import AppKit
import SwiftUI

/// Top-right corner of the panel: compact/full toggle, pin, settings, quit.
struct PanelCornerButtons: View {
    @ObservedObject var preferences: Preferences
    let openSettings: () -> Void

    var body: some View {
        // Vertical arrows: the switch changes the player's height. (Diagonal arrows mean full screen.)
        let isCompact = preferences.compactPlayer
        let pinned = preferences.pinPlayer
        IconButton(
            symbol: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
            help: isCompact ? "Full player" : "Compact player"
        ) { preferences.compactPlayer.toggle() }
        Button { preferences.pinPlayer.toggle() } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin (close when clicking elsewhere)" : "Pin open")
        .pointingHandCursor()
        .playerButtonHover(
            from: pinned ? Color(preferences.accentColor) : .secondary,
            to: pinned ? Color(preferences.accentColor) : .primary
        )
        IconButton(symbol: "gearshape", help: "Settings", action: openSettings)
        IconButton(symbol: "power", help: "Quit \(AppInfo.name)") { NSApp.terminate(nil) }
    }
}

/// Shows or hides the visualizer column.
struct VisualizerToggle: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        ToggleButton(symbol: "waveform", isOn: preferences.showVisualizer, help: "Visualizer") {
            preferences.showVisualizer.toggle()
        }
    }
}

/// Turns the floating lyrics on and off; a crossed-out mic when the song has none.
struct LyricsToggle: View {
    @ObservedObject var lyrics: LyricsSession

    var body: some View {
        ToggleButton(
            symbol: lyrics.hasNoLyrics ? "mic.slash" : "music.mic",
            isOn: lyrics.isEnabled,
            help: "Lyrics",
            helpOverride: lyrics.hasNoLyrics ? "Lyrics on – \(lyrics.statusText)" : nil
        ) { lyrics.isEnabled.toggle() }
    }
}

/// ‹ name › above the visualizer: steps back and forward through the visuals.
struct VisualizerStepper: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", help: "Previous visual") {
                preferences.visualizerStyle = preferences.visualizerStyle.previous
            }
            Text(preferences.visualizerStyle.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            stepButton("chevron.right", help: "Next visual") {
                preferences.visualizerStyle = preferences.visualizerStyle.next
            }
        }
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHandCursor()
        .playerButtonHover(from: .secondary)
    }
}
