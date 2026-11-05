import Combine
import Foundation

/// Menu bar and player appearance options, kept between launches.
@MainActor
package final class Preferences: ObservableObject {
    package nonisolated static let defaultAccent = SRGBColor(red: 0x1E, green: 0xD7, blue: 0x60) // Spotify green
    package static let maxTextLengthRange: ClosedRange<Double> = 15...80

    private enum Key {
        static let menuBarTextStyle = "menuBarTextStyle"
        static let maxTextLength = "menuBarMaxTextLength"
        static let showLikeButton = "menuBarShowLikeButton"
        static let showLyricsButton = "menuBarShowLyricsButton"
        static let menuBarBackground = "menuBarBackground"
        static let accent = "accentHex"
        static let pinPlayer = "pinPlayer"
        static let showVisualizer = "showVisualizer"
        static let visualizerStyle = "visualizerStyle"
        static let compactPlayer = "compactPlayer"
    }

    // MARK: Menu bar

    @Published package var menuBarTextStyle: MenuBarTextStyle {
        didSet { storage.set(menuBarTextStyle.rawValue, forKey: Key.menuBarTextStyle) }
    }
    /// Characters before the menu bar text is cut off with "…".
    @Published package var maxTextLength: Double {
        didSet { storage.set(maxTextLength, forKey: Key.maxTextLength) }
    }
    @Published package var showLikeButton: Bool {
        didSet { storage.set(showLikeButton, forKey: Key.showLikeButton) }
    }
    /// The lyrics icon only shows while lyrics are off.
    @Published package var showLyricsButton: Bool {
        didSet { storage.set(showLyricsButton, forKey: Key.showLyricsButton) }
    }
    @Published package var menuBarBackground: MenuBarBackground {
        didSet { storage.set(menuBarBackground.rawValue, forKey: Key.menuBarBackground) }
    }

    // MARK: Player

    @Published package var accentColor: SRGBColor {
        didSet { storage.set(accentColor.hex, forKey: Key.accent) }
    }
    /// Keep the player open when clicking elsewhere (it then closes only from the menu bar).
    @Published package var pinPlayer: Bool {
        didSet { storage.set(pinPlayer, forKey: Key.pinPlayer) }
    }
    /// Live audio visualizer to the right of the full player.
    @Published package var showVisualizer: Bool {
        didSet { storage.set(showVisualizer, forKey: Key.showVisualizer) }
    }
    @Published package var visualizerStyle: VisualizerStyle {
        didSet { storage.set(visualizerStyle.rawValue, forKey: Key.visualizerStyle) }
    }
    /// One-row player bar instead of the full player.
    @Published package var compactPlayer: Bool {
        didSet { storage.set(compactPlayer, forKey: Key.compactPlayer) }
    }

    private let storage: SettingsStorage

    package init(storage: SettingsStorage) {
        self.storage = storage
        menuBarTextStyle = storage.value(forKey: Key.menuBarTextStyle).flatMap(MenuBarTextStyle.init) ?? .artistTitle
        maxTextLength = storage.value(forKey: Key.maxTextLength) ?? 40
        showLikeButton = storage.value(forKey: Key.showLikeButton) ?? true
        showLyricsButton = storage.value(forKey: Key.showLyricsButton) ?? true
        menuBarBackground = storage.value(forKey: Key.menuBarBackground).flatMap(MenuBarBackground.init) ?? .none
        accentColor = storage.value(forKey: Key.accent).flatMap { SRGBColor(hex: $0) } ?? Self.defaultAccent
        pinPlayer = storage.value(forKey: Key.pinPlayer) ?? false
        showVisualizer = storage.value(forKey: Key.showVisualizer) ?? true
        visualizerStyle = storage.value(forKey: Key.visualizerStyle).flatMap { VisualizerStyle(storedValue: $0) } ?? .analyzer
        compactPlayer = storage.value(forKey: Key.compactPlayer) ?? false
    }

    package var isDefaultAccent: Bool { accentColor == Self.defaultAccent }

    package func resetAccent() {
        accentColor = Self.defaultAccent
    }

    package func setAccent(_ channel: SRGBColor.Channel, to value: Int) {
        accentColor[channel] = value
    }
}
