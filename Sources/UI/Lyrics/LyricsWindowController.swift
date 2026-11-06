import AppDomain
import AppKit
import Combine
import SwiftUI

/// The single floating lyrics window. It sits at the default position chosen in settings (or
/// wherever it was dragged by its handle). The window is larger than the visible lyrics, so
/// it only accepts the mouse while the pointer is over them: everywhere else clicks pass
/// through to what's underneath.
@MainActor
final class LyricsWindowController {
    private static let pillWindowSize = NSSize(width: 760, height: 160) // five lines, gap and shadow
    private static let expandedWidth: CGFloat = 600
    private static let screenMargin: CGFloat = 10
    private static let mousePollInterval: TimeInterval = 1.0 / 30

    private let lyrics: LyricsSession
    private let preferences: LyricsPreferences
    private let nowPlaying: NowPlaying
    private let likedSongs: LikedSongs
    private let account: SpotifyAccount
    private let state = LyricsWindowState()
    private var window: NSPanel?
    private var mouseTimer: Timer?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isShowingCustomCursor = false
    private var cancellables = Set<AnyCancellable>()

    init(
        lyrics: LyricsSession,
        preferences: LyricsPreferences,
        nowPlaying: NowPlaying,
        likedSongs: LikedSongs,
        account: SpotifyAccount
    ) {
        self.lyrics = lyrics
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.likedSongs = likedSongs
        self.account = account
        BackgroundCursor.allowSettingCursorWhileInBackground()

        state.onDragChanged = { [weak self] in self?.dragChanged() }
        state.onDragEnded = { [weak self] in self?.dragEnded() }
        state.onReset = { [weak preferences] in preferences?.resetPosition() }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.updateWindow() }
            .store(in: &cancellables)
        preferences.positionResetRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.moveToDefaultPosition() }
            .store(in: &cancellables)
        lyrics.$isEnabled.removeDuplicates().map { _ in () }
            .merge(with: preferences.$isExpanded.removeDuplicates().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateWindow() }
            .store(in: &cancellables)
    }

    private func moveToDefaultPosition() {
        preferences.windowAnchor = nil
        guard lyrics.isEnabled, let window else { return }
        window.setFrame(targetFrame(), display: true, animate: true)
    }

    // MARK: Placement

    private static var primaryScreen: NSScreen? { NSScreen.screens.first }

    /// Top centre of the window, if it was dragged somewhere that's still on a screen.
    private var savedAnchor: NSPoint? {
        guard let anchor = preferences.windowAnchor else { return nil }
        return screen(containing: anchor) != nil ? anchor : nil
    }

    /// Top centre of the window for the chosen default position.
    private func defaultAnchor(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let halfWidth = Self.pillWindowSize.width / 2
        switch preferences.defaultPosition {
        case .topCenter: return NSPoint(x: visible.midX, y: visible.maxY)
        case .topLeft: return NSPoint(x: visible.minX + halfWidth, y: visible.maxY)
        case .topRight: return NSPoint(x: visible.maxX - halfWidth, y: visible.maxY)
        case .center: return NSPoint(x: visible.midX, y: visible.midY + Self.pillWindowSize.height / 2)
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        // Nudge down: the default anchor sits exactly on the menu bar's bottom edge.
        let probe = NSPoint(x: point.x, y: point.y - 1)
        return NSScreen.screens.first { $0.frame.contains(probe) }
    }

    private func targetFrame() -> NSRect {
        guard let primary = Self.primaryScreen else { return .zero }
        let saved = savedAnchor
        let targetScreen = saved.flatMap { screen(containing: $0) } ?? primary
        let anchor = saved ?? defaultAnchor(on: targetScreen)
        let visible = targetScreen.visibleFrame

        guard preferences.isExpanded else {
            let size = Self.pillWindowSize
            return NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height, width: size.width, height: size.height)
        }
        // Nearly the full screen height. Horizontally: where it was dragged, else per the default.
        let width = Self.expandedWidth, margin = Self.screenMargin
        let x: CGFloat
        switch (saved, preferences.defaultPosition) {
        case (nil, .topLeft): x = visible.minX + margin
        case (nil, .topRight): x = visible.maxX - width - margin
        default: x = min(max(anchor.x - width / 2, visible.minX), visible.maxX - width)
        }
        return NSRect(x: x, y: visible.minY + margin, width: width, height: visible.height - margin * 2)
    }

    private func updateWindow() {
        guard lyrics.isEnabled else {
            window?.orderOut(nil)
            stopMouseTracking()
            return
        }
        let window = self.window ?? makeWindow()
        window.setFrame(targetFrame(), display: true)
        window.orderFrontRegardless()
        startMouseTracking()
    }

    private func makeWindow() -> NSPanel {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LyricsWindowRootView(
            lyrics: lyrics, preferences: preferences, nowPlaying: nowPlaying, state: state,
            likedSongs: likedSongs, account: account
        ))
        self.window = window
        return window
    }

    // MARK: Mouse

    /// Polls the pointer (cheap) instead of relying on hover events, which a non-activating
    /// panel of a background app doesn't reliably get.
    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: Self.mousePollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseState() }
        }
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        state.isHovering = false
        state.hoveredID = nil
        restoreCursor()
    }

    private func screenRect(_ frame: CGRect, in window: NSWindow) -> NSRect {
        NSRect(x: window.frame.minX + frame.minX, y: window.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    private func updateMouseState() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let isDragging = dragStartMouse != nil
        let content = state.contentFrame
        let isOver = isDragging || (!content.isEmpty && screenRect(content, in: window).contains(mouse))

        if window.ignoresMouseEvents == isOver { window.ignoresMouseEvents = !isOver }
        if state.isHovering != isOver { state.isHovering = isOver }

        let hovered = isOver ? clickableID(at: mouse, in: window) : nil
        if state.hoveredID != hovered { state.hoveredID = hovered }

        // Re-assert every tick: other apps reset the cursor as it moves.
        if isDragging {
            NSCursor.closedHand.set()
            isShowingCustomCursor = true
        } else if hovered == LyricsWindowState.handleID {
            NSCursor.openHand.set()
            isShowingCustomCursor = true
        } else if hovered != nil {
            NSCursor.pointingHand.set()
            isShowingCustomCursor = true
        } else {
            restoreCursor()
        }
    }

    /// Controls win over lines (they can overlap the pill's text); lines only count where
    /// they're actually visible in the expanded view's scroll area.
    private func clickableID(at mouse: NSPoint, in window: NSWindow) -> String? {
        let hits = state.clickableFrames.filter { screenRect($0.value, in: window).contains(mouse) }.map(\.key)
        if let control = hits.first(where: { !LyricsWindowState.isLineID($0) }) { return control }
        let viewport = state.viewportFrame
        if preferences.isExpanded, !viewport.isEmpty, !screenRect(viewport, in: window).contains(mouse) { return nil }
        return hits.first
    }

    private func restoreCursor() {
        guard isShowingCustomCursor else { return }
        NSCursor.arrow.set()
        isShowingCustomCursor = false
    }

    // MARK: Dragging (by the handle)

    private func dragChanged() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = window.frame.origin
        }
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        window.setFrameOrigin(NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y))
    }

    private func dragEnded() {
        defer {
            dragStartMouse = nil
            dragStartOrigin = nil
        }
        guard let window else { return }
        // The expanded view always spans the screen height, so only its x position counts.
        let anchorY = preferences.isExpanded ? expandedAnchorY(for: window) : window.frame.maxY
        preferences.windowAnchor = NSPoint(x: window.frame.midX, y: anchorY)
        if preferences.isExpanded { window.setFrame(targetFrame(), display: true, animate: true) }
    }

    private func expandedAnchorY(for window: NSWindow) -> CGFloat {
        if let saved = savedAnchor { return saved.y }
        let screen = screen(containing: NSPoint(x: window.frame.midX, y: window.frame.maxY)) ?? Self.primaryScreen
        return screen?.visibleFrame.maxY ?? window.frame.maxY
    }
}
