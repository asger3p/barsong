import AppDomain
import AppKit
import Combine
import SwiftUI

/// One status item whose trailing icons are separate click targets (lyrics toggle, Liked
/// Songs); clicks anywhere else open the panel. Also owns the panel and the lyrics window.
@MainActor
package final class StatusBarController: NSObject {
    private let models: AppModels
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let label: ClickThroughHostingView<MenuBarLabel>
    private var lyricsWindow: LyricsWindowController?
    private lazy var settingsWindow = SettingsWindowController(models: models)
    private lazy var fullScreen: FullScreenController = {
        let controller = FullScreenController(models: models)
        controller.onVisibilityChange = { [weak self] in self?.updateAudioCapture() }
        return controller
    }()
    private var cancellables = Set<AnyCancellable>()

    package init(models: AppModels) {
        self.models = models
        label = ClickThroughHostingView(rootView: MenuBarLabel(
            nowPlaying: models.nowPlaying, likedSongs: models.likedSongs, account: models.account,
            lyrics: models.lyrics, preferences: models.preferences
        ))
        super.init()
        setUpPopover()
        guard let button = statusItem.button else { return }
        lyricsWindow = LyricsWindowController(
            lyrics: models.lyrics, preferences: models.lyricsPreferences, nowPlaying: models.nowPlaying,
            likedSongs: models.likedSongs, account: models.account
        )
        setUpButton(button)
        observeModels()
        updateLength()
    }

    private func setUpPopover() {
        let panel = NowPlayingPanel(
            models: models,
            openSettings: { [weak self] in self?.showSettings() },
            openFullScreen: { [weak self] in self?.showFullScreen() }
        )
        let hostingController = NSHostingController(rootView: panel)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        popover.delegate = self
        // Pinned: the panel stays open when clicking elsewhere; the menu bar item still closes it.
        models.preferences.$pinPlayer
            .sink { [weak self] pinned in self?.popover.behavior = pinned ? .applicationDefined : .transient }
            .store(in: &cancellables)
    }

    private func setUpButton(_ button: NSStatusBarButton) {
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeModels() {
        // Resize the status item whenever the label's content may have changed.
        models.nowPlaying.objectWillChange
            .merge(with: models.likedSongs.objectWillChange, models.account.objectWillChange, models.preferences.objectWillChange)
            .merge(with: models.lyrics.$isEnabled.map { _ in () }.eraseToAnyPublisher())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLength()
                self?.updateAudioCapture()
            }
            .store(in: &cancellables)
        // Resize once the label has actually re-rendered at its new size, so a newly shown
        // icon (like the lyrics mic) isn't cut off by a status item that's still too narrow.
        label.onSizeChange = { [weak self] in
            DispatchQueue.main.async { self?.updateLength() }
        }
        // Loudness and key are measured per track.
        models.nowPlaying.$track
            .map { $0?.uri }
            .removeDuplicates()
            .sink { [weak self] _ in self?.models.visualizer.startNewTrack() }
            .store(in: &cancellables)
        // Back to the panel after signing in in the browser.
        models.account.didConnect
            .sink { NSApp.activate(ignoringOtherApps: true) }
            .store(in: &cancellables)
    }

    private func updateLength() {
        label.layoutSubtreeIfNeeded()
        let width = ceil(label.fittingSize.width)
        if statusItem.length != width { statusItem.length = width }
    }

    // MARK: Clicks

    /// The visible trailing icons, right to left (mirrors `MenuBarLabel`).
    private var trailingIcons: [MenuBarLayout.ClickTarget] {
        guard models.nowPlaying.track != nil else { return [] }
        let preferences = models.preferences
        var icons: [MenuBarLayout.ClickTarget] = []
        if preferences.showLyricsButton && !models.lyrics.isEnabled { icons.append(.lyricsIcon) }
        if preferences.showLikeButton && models.likedSongs.showsLikeButton { icons.append(.likeIcon) }
        return icons
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let clickX = NSApp.currentEvent.map { button.convert($0.locationInWindow, from: nil).x } ?? 0
        let target = MenuBarLayout.clickTarget(
            atX: clickX, width: button.bounds.width,
            trailingIcons: trailingIcons, background: models.preferences.menuBarBackground
        )
        switch target {
        case .lyricsIcon:
            models.lyrics.isEnabled.toggle()
        case .likeIcon where models.account.isConnected:
            Task { await models.likedSongs.toggleCurrentTrack() }
        case .likeIcon, .label:
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            models.nowPlaying.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            updateAudioCapture()
        }
    }

    private func showFullScreen() {
        popover.performClose(nil)
        fullScreen.show()
    }

    private func showSettings() {
        if popover.behavior == .transient { popover.performClose(nil) }
        settingsWindow.show()
    }

    /// Spotify's audio is only captured while the visualizer is on screen and the music plays.
    /// Paused, it stops listening but holds the picture.
    private func updateAudioCapture() {
        let visualizer = models.visualizer
        let preferences = models.preferences
        let isInPanel = popover.isShown && preferences.showVisualizer && !preferences.compactPlayer
        let isOnScreen = (isInPanel || fullScreen.isShown) && models.nowPlaying.track != nil
        switch (isOnScreen, models.nowPlaying.isPlaying) {
        case (false, _):
            if visualizer.status != .stopped { visualizer.stop() }
        case (true, true):
            if visualizer.status != .running { visualizer.start() }
        case (true, false):
            visualizer.pause()
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    package func popoverDidClose(_ notification: Notification) {
        updateAudioCapture()
    }
}
