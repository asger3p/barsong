import SwiftUI

/// Shuffle, repeat, lyrics, visualizer: the accent colour with a dot underneath when on, like Spotify.
struct ToggleButton: View {
    @Environment(\.playerAccent) private var accent
    let symbol: String
    let isOn: Bool
    let help: String
    /// Replaces the "… on/off" tooltip.
    var helpOverride: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Circle().frame(width: 4, height: 4).opacity(isOn ? 1 : 0)
            }
            .foregroundStyle(isOn ? accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(helpOverride ?? help + (isOn ? " on" : " off"))
        .pointingHandCursor()
    }
}

/// Play/pause, previous, next.
struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

/// Small grey icon button (settings, quit, compact toggle).
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .pointingHandCursor()
    }
}
