import AppDomain
import AppKit
import SwiftUI

/// Cover · text · like icon · lyrics icon (only while lyrics are off).
struct MenuBarLabel: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var likedSongs: LikedSongs
    @ObservedObject var lyrics: LyricsSession
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: MenuBarLayout.itemSpacing) {
            if let track = nowPlaying.track {
                leadingIcon
                if let text = preferences.menuBarTextStyle.text(for: track, maxLength: Int(preferences.maxTextLength)) {
                    Text(text)
                }
                if preferences.showLikeButton && likedSongs.canLikeCurrentTrack {
                    Image(systemName: likedSongs.isCurrentTrackLiked == true ? "checkmark.circle.fill" : "plus.circle")
                        .frame(width: MenuBarLayout.trailingIconWidth)
                }
                if preferences.showLyricsButton && !lyrics.isEnabled {
                    Image(systemName: "music.mic.circle")
                        .frame(width: MenuBarLayout.trailingIconWidth)
                }
            } else {
                Image(systemName: Self.placeholderSymbol) // nothing playing
            }
        }
        .font(Font(NSFont.menuBarFont(ofSize: 0)))
        .foregroundStyle(usesAlbumPill ? Color.white : Color.primary)
        .padding(.horizontal, MenuBarLayout.innerPadding(for: background))
        .padding(.vertical, background == .none ? 0 : 2)
        .background { backgroundShape }
        .padding(.horizontal, MenuBarLayout.outerPadding(for: background))
        .animation(.easeInOut(duration: 0.5), value: nowPlaying.albumPalette)
        .fixedSize()
    }

    /// No pill while nothing is playing: just the note.
    private var background: MenuBarBackground {
        nowPlaying.track == nil ? .none : preferences.menuBarBackground
    }

    private var usesAlbumPill: Bool {
        background == .album && nowPlaying.albumPalette != nil
    }

    @ViewBuilder
    private var backgroundShape: some View {
        let plain = Color.primary.opacity(0.14)
        switch background {
        case .none: EmptyView()
        case .pill: Capsule().fill(plain)
        case .album:
            if let palette = nowPlaying.albumPalette {
                Capsule().fill(palette.gradient)
            } else {
                Capsule().fill(plain)
            }
        }
    }

    /// Stands in for the cover while nothing plays or the cover is still loading.
    private static let placeholderSymbol = "music.note"

    /// The album cover, dimmed with a pause badge while paused. A note (or a pause symbol)
    /// until the cover has loaded.
    @ViewBuilder
    private var leadingIcon: some View {
        if let image = ArtworkImages.image(for: nowPlaying.artwork) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .opacity(nowPlaying.isPlaying ? 1 : 0.45)
                .overlay {
                    if !nowPlaying.isPlaying {
                        Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                    }
                }
        } else if nowPlaying.isPlaying {
            Image(systemName: Self.placeholderSymbol)
        } else {
            Image(systemName: "pause.fill")
        }
    }
}

/// Hosting view that ignores clicks, so the status item button underneath receives them.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Called whenever SwiftUI's content changes size (an icon appears or disappears).
    var onSizeChange: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}
