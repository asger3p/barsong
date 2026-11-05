import AppKit
import SwiftUI

/// Copies the track's Spotify link to the clipboard and says so in a small bubble above it.
/// Laid out like the toggles beside it (icon over a dot-sized gap), so the row lines up.
struct ShareLinkButton: View {
    @Environment(\.playerAccent) private var accent
    let url: URL
    @State private var copiedAt: Date?

    private static let confirmationDuration: TimeInterval = 1.5

    var body: some View {
        Button(action: copy) {
            VStack(spacing: 3) {
                Image(systemName: isShowingConfirmation ? "doc.on.doc.fill" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                Color.clear.frame(width: 4, height: 4)
            }
            .foregroundStyle(isShowingConfirmation ? accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy Spotify link")
        .pointingHandCursor()
        .overlay(alignment: .top) {
            if isShowingConfirmation {
                Text("Copied to clipboard")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .fixedSize()
                    .offset(y: -24)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isShowingConfirmation)
    }

    private var isShowingConfirmation: Bool { copiedAt != nil }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        let copied = Date()
        copiedAt = copied
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationDuration) {
            if copiedAt == copied { copiedAt = nil }
        }
    }
}
