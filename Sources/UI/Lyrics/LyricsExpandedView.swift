import AppDomain
import SwiftUI

/// Full-height view of the whole song, Spotify-style: big bold lines, the current one bright
/// and kept centred, past lines dimmed. Click any line to jump there.
struct LyricsExpandedView: View {
    @ObservedObject var lyrics: LyricsSession
    @ObservedObject var preferences: LyricsPreferences
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var state: LyricsWindowState
    @ObservedObject var likedSongs: LikedSongs
    /// Observed so the like button appears and disappears with the connection.
    @ObservedObject var account: SpotifyAccount

    static let shadowMargin: CGFloat = 12
    private static let cornerRadius: CGFloat = 22

    var body: some View {
        let textColor = preferences.pillStyle.textColor
        Group {
            if let track = nowPlaying.track {
                VStack(alignment: .leading, spacing: 0) {
                    header(track, textColor: textColor)
                    content(textColor: textColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .modifier(PillBackground(style: preferences.pillStyle, palette: nowPlaying.albumPalette, cornerRadius: Self.cornerRadius))
                .reportsLyricsContentFrame()
            } else {
                Color.clear
            }
        }
        .padding(Self.shadowMargin)
    }

    private func header(_ track: Track, textColor: Color) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(textColor)
                Text(track.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            LyricsLikeButton(likedSongs: likedSongs, account: account, state: state, textColor: textColor, size: 13)
            LyricsWindowControls(lyrics: lyrics, preferences: preferences, state: state, size: 12)
        }
        .padding(.leading, 24)
        .padding(.trailing, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func content(textColor: Color) -> some View {
        if !lyrics.timeline.isEmpty {
            syncedLyrics(textColor: textColor)
        } else if let plain = lyrics.plainLyrics {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("These lyrics aren't synced", systemImage: "clock.badge.xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.5))
                    Text(plain)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(textColor.opacity(0.8))
                        .lineSpacing(8)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: lyrics.status == .loading ? "ellipsis" : "mic.slash")
                    .font(.system(size: 28))
                Text(lyrics.statusText)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(textColor.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncedLyrics(textColor: Color) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(lyrics.timeline.lines.enumerated()), id: \.offset) { index, line in
                            let id = LyricsWindowState.lineID(index)
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(textColor.opacity(opacity(for: index, hovered: state.hoveredID == id)))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { lyrics.seek(toLine: index) }
                                .lyricsClickable(id)
                                .animation(.easeOut(duration: 0.3), value: lyrics.currentLineIndex)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    // Lets the first and last lines scroll to the centre too.
                    .padding(.vertical, geometry.size.height / 2)
                }
                .background(GeometryReader { viewport in
                    Color.clear.preference(key: LyricsViewportKey.self, value: viewport.frame(in: .global))
                })
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onAppear {
                    if let current = lyrics.currentLineIndex { proxy.scrollTo(current, anchor: .center) }
                }
                .onChange(of: lyrics.currentLineIndex) { current in
                    guard let current else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
    }

    /// The current line bright, past lines dim, upcoming lines in between.
    private func opacity(for index: Int, hovered: Bool) -> Double {
        guard let current = lyrics.currentLineIndex else { return hovered ? 0.9 : 0.6 }
        if index == current { return 1 }
        if hovered { return 0.9 }
        return index < current ? 0.35 : 0.6
    }
}

struct LyricsWindowRootView: View {
    let lyrics: LyricsSession
    @ObservedObject var preferences: LyricsPreferences
    let nowPlaying: NowPlaying
    let state: LyricsWindowState
    let likedSongs: LikedSongs
    let account: SpotifyAccount

    var body: some View {
        Group {
            if preferences.isExpanded {
                LyricsExpandedView(
                    lyrics: lyrics, preferences: preferences, nowPlaying: nowPlaying, state: state,
                    likedSongs: likedSongs, account: account
                )
            } else {
                LyricsPillView(lyrics: lyrics, preferences: preferences, nowPlaying: nowPlaying, state: state)
            }
        }
        .onPreferenceChange(LyricsContentFrameKey.self) { state.contentFrame = $0 }
        .onPreferenceChange(LyricsClickableFramesKey.self) { state.clickableFrames = $0 }
        .onPreferenceChange(LyricsViewportKey.self) { state.viewportFrame = $0 }
    }
}
