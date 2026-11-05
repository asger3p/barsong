import AppDomain
import SwiftUI

/// A rounded pill floating just below the menu bar. Shows the current line (bright) with
/// optional surrounding lines (dimmed); rows scroll up as the song moves on. Click a line to
/// jump to it; hover for the controls in the top-right corner.
struct LyricsPillView: View {
    @ObservedObject var lyrics: LyricsSession
    @ObservedObject var preferences: LyricsPreferences
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var state: LyricsWindowState

    static let gapBelowMenuBar: CGFloat = 6
    private static let cornerRadius: CGFloat = 15
    private static let controlSize: CGFloat = 9
    private static let maxWidth: CGFloat = 680
    private static let scroll = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Four icons plus spacing and the corner inset.
    private static var controlsWidth: CGFloat {
        4 * (controlSize + 8) + 3 * (controlSize * 0.7) + 4
    }

    var body: some View {
        let visibleLines = lyrics.visibleLines
        let notice = lyrics.unavailableNotice
        let alignment = Alignment(horizontal: preferences.defaultPosition.horizontalAlignment, vertical: .top)
        VStack(spacing: 0) {
            if !visibleLines.isEmpty || notice != nil {
                pill(lines: visibleLines, notice: notice)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Self.gapBelowMenuBar)
        .padding(.horizontal, 12) // room for the shadow when aligned to a side
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(Self.scroll, value: lyrics.currentLineIndex)
        .animation(Self.scroll, value: visibleLines.isEmpty)
        .animation(Self.scroll, value: notice)
        .animation(Self.scroll, value: preferences.visibleLineCount)
        .animation(Self.scroll, value: preferences.pillStyle)
        .animation(.easeOut(duration: 0.15), value: state.isHovering)
    }

    private func pill(lines: [VisibleLyricLine], notice: String?) -> some View {
        let textColor = preferences.pillStyle.textColor
        return VStack(spacing: 3) {
            if lines.isEmpty, let notice {
                Label(notice, systemImage: "mic.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineLimit(1)
            }
            ForEach(lines) { line in
                let id = LyricsWindowState.lineID(line.id)
                Text(line.text)
                    .font(.system(size: line.isCurrent ? 13 : 12, weight: line.isCurrent ? .semibold : .medium))
                    .foregroundStyle(textColor.opacity(line.isCurrent || state.hoveredID == id ? 1 : 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture { lyrics.seek(toLine: line.id) }
                    .lyricsClickable(id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, lines.count > 1 ? 8 : 0)
        // On hover, make room on the right so the controls don't cover the words.
        .padding(.trailing, state.isHovering ? Self.controlsWidth : 0)
        .frame(minHeight: 30)
        .frame(maxWidth: Self.maxWidth)
        .overlay(alignment: .topTrailing) {
            if state.isHovering {
                LyricsWindowControls(lyrics: lyrics, preferences: preferences, state: state, size: Self.controlSize)
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .modifier(PillBackground(style: preferences.pillStyle, palette: nowPlaying.albumPalette, cornerRadius: Self.cornerRadius))
        .reportsLyricsContentFrame()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
