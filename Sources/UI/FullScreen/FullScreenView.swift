import AppDomain
import SwiftUI

/// The full-screen view: the player on the left, every visual at once on the right. Click a
/// visual to fill the space with it; "All visuals" goes back to the grid.
struct FullScreenView: View {
    let models: AppModels
    let close: () -> Void
    @ObservedObject private var nowPlaying: NowPlaying
    @ObservedObject private var preferences: Preferences
    @State private var focusedStyle: VisualizerStyle?

    private static let playerWidth: CGFloat = 360
    private static let columns = 3
    private static let spacing: CGFloat = 14

    init(models: AppModels, close: @escaping () -> Void) {
        self.models = models
        self.close = close
        nowPlaying = models.nowPlaying
        preferences = models.preferences
    }

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            player
                .frame(width: Self.playerWidth)
            visuals
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .topTrailing) { closeButton }
        .environment(\.playerAccent, Color(preferences.accentColor))
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            Color.black
            if let palette = nowPlaying.albumPalette {
                palette.gradient.opacity(0.35)
                    .animation(.easeInOut(duration: 1), value: palette)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Player

    @ViewBuilder
    private var player: some View {
        if let track = nowPlaying.track {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                ArtworkView(nowPlaying: nowPlaying, size: Self.playerWidth, cornerRadius: 14)
                TrackInfo(models: models, track: track)
                TransportControls(nowPlaying: nowPlaying, isCompact: false)
                PlaybackProgress(nowPlaying: nowPlaying, track: track, isCompact: false)
                HStack(spacing: 12) {
                    Spacer()
                    if let url = track.shareURL {
                        ShareLinkButton(url: url)
                    }
                    LyricsToggle(lyrics: models.lyrics)
                    VolumeControl(nowPlaying: nowPlaying).frame(width: 150)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "music.note.list").font(.system(size: 48)).foregroundStyle(.secondary)
                Text(nowPlaying.isPlayerRunning ? "Nothing playing" : "Spotify isn't running").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: Visuals

    private var visuals: some View {
        LiveVisualizerTimeline(visualizer: models.visualizer, isPlaying: nowPlaying.isPlaying) { frame, date in
            let surroundings = VisualizerSurroundings(accent: Color(preferences.accentColor), date: date, spotifyVolume: nowPlaying.volume)
            Group {
                if let style = focusedStyle {
                    focused(style, frame: frame, surroundings: surroundings)
                } else {
                    grid(frame: frame, surroundings: surroundings)
                }
            }
            .overlay(alignment: .bottom) {
                if let issue = models.visualizer.issue(isPlaying: nowPlaying.isPlaying, now: Date()) {
                    VisualizerIssueMessage(issue: issue)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.7)))
                        .padding(.bottom, 12)
                }
            }
        }
    }

    /// Every visual at once, sized to fit without scrolling.
    private func grid(frame: VisualizerFrame, surroundings: VisualizerSurroundings) -> some View {
        GeometryReader { geometry in
            let styles = VisualizerStyle.allCases
            let rows = Int((Double(styles.count) / Double(Self.columns)).rounded(.up))
            let tileWidth = (geometry.size.width - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            let tileHeight = (geometry.size.height - Self.spacing * CGFloat(rows - 1)) / CGFloat(rows)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: Self.spacing), count: Self.columns), spacing: Self.spacing) {
                ForEach(styles) { style in
                    tile(style, frame: frame, surroundings: surroundings)
                        .frame(width: tileWidth, height: tileHeight)
                }
            }
        }
    }

    private func tile(_ style: VisualizerStyle, frame: VisualizerFrame, surroundings: VisualizerSurroundings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(style.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VisualizerCanvas(style: style, frame: frame, surroundings: surroundings)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { focusedStyle = style } }
        .pointingHandCursor()
        .help("Show \(style.label) large")
    }

    private func focused(_ style: VisualizerStyle, frame: VisualizerFrame, surroundings: VisualizerSurroundings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { focusedStyle = nil }
                } label: {
                    Label("All visuals", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pointingHandCursor()
                stepper(style)
            }
            .font(.callout.weight(.semibold))
            VisualizerCanvas(style: style, frame: frame, surroundings: surroundings)
                .contentShape(Rectangle())
                .onTapGesture { focusedStyle = style.next }
                .pointingHandCursor()
                .help("Click for the next visual")
        }
    }

    private func stepper(_ style: VisualizerStyle) -> some View {
        HStack(spacing: 8) {
            Button { focusedStyle = style.previous } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Previous visual")
            Text(style.label)
            Button { focusedStyle = style.next } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Next visual")
        }
        .foregroundStyle(.primary)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Leave full screen (Esc)")
        .pointingHandCursor()
        .padding(14)
    }
}
