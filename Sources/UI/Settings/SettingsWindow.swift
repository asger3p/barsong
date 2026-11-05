import AppDomain
import AppKit
import SwiftUI

/// The settings categories in the window's sidebar.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, player, menuBar, lyrics, spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .player: "Player"
        case .menuBar: "Menu Bar"
        case .lyrics: "Lyrics"
        case .spotify: "Spotify Account"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .player: "play.circle"
        case .menuBar: "menubar.rectangle"
        case .lyrics: "music.mic"
        case .spotify: "person.crop.circle"
        }
    }
}

/// The settings window: categories in a sidebar, the chosen one on the right.
struct SettingsView: View {
    let models: AppModels
    @State private var category: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $category) { category in
                Label(category.title, systemImage: category.symbol)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    page(for: category ?? .general)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The window is titled with the app's name; the chosen category shows underneath.
        .navigationTitle(AppInfo.name)
        .navigationSubtitle((category ?? .general).title)
        .environment(\.playerAccent, Color(models.preferences.accentColor))
    }

    @ViewBuilder
    private func page(for category: SettingsCategory) -> some View {
        switch category {
        case .general: GeneralSettingsPage(loginItem: models.loginItem)
        case .player: PlayerSettingsPage(preferences: models.preferences)
        case .menuBar: MenuBarSettingsPage(preferences: models.preferences)
        case .lyrics: LyricsSettingsPage(lyrics: models.lyrics, preferences: models.lyricsPreferences)
        case .spotify: SettingsSection(title: "Liked Songs") { AccountSettings(account: models.account) }
        }
    }
}

/// Opens the settings window, creating it the first time.
@MainActor
final class SettingsWindowController {
    private let models: AppModels
    private var window: NSWindow?

    init(models: AppModels) {
        self.models = models
    }

    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
        window.contentViewController = NSHostingController(rootView: SettingsView(models: models))
        window.setContentSize(NSSize(width: 660, height: 500))
        window.contentMinSize = NSSize(width: 560, height: 380)
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }
}

// MARK: Pages

struct GeneralSettingsPage: View {
    let loginItem: LoginItem
    @State private var launchAtLogin = false

    var body: some View {
        SettingsSection(title: "Startup") {
            SettingsToggleRow(title: "Open \(AppInfo.name) at login", isOn: $launchAtLogin)
                .onAppear { launchAtLogin = loginItem.isEnabled }
                .onChange(of: launchAtLogin) { enabled in
                    guard enabled != loginItem.isEnabled else { return }
                    do {
                        try loginItem.setEnabled(enabled)
                    } catch {
                        NSLog("Barsong launch-at-login error: \(error)")
                        launchAtLogin = loginItem.isEnabled
                    }
                }
        }
        AboutFooter()
            .padding(.top, 8)
    }
}

struct PlayerSettingsPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsSection(title: "Layout") {
            SettingsToggleRow(title: "Compact layout", isOn: $preferences.compactPlayer)
            SettingsToggleRow(title: "Keep the player open when clicking elsewhere", isOn: $preferences.pinPlayer)
        }
        SettingsSection(title: "Visualizer") {
            SettingsToggleRow(title: "Show the visualizer", isOn: $preferences.showVisualizer)
            if preferences.showVisualizer {
                SettingsPickerRow(
                    title: "Visual",
                    hint: preferences.compactPlayer ? "Shown in the full layout" : "Or click the visualizer to cycle",
                    selection: $preferences.visualizerStyle,
                    options: VisualizerStyle.allCases,
                    label: \.label
                )
            }
        }
        ColourSettings(preferences: preferences)
    }
}

struct MenuBarSettingsPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsSection(title: "Text") {
            SettingsPickerRow(title: "Show", selection: $preferences.menuBarTextStyle, options: MenuBarTextStyle.allCases, label: \.label)
            if preferences.menuBarTextStyle != .hidden {
                HStack {
                    Text("Max length")
                    Slider(value: $preferences.maxTextLength, in: Preferences.maxTextLengthRange, step: 5)
                        .pointingHandCursor()
                    Text("\(Int(preferences.maxTextLength))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        SettingsSection(title: "Look") {
            SettingsPickerRow(title: "Background", selection: $preferences.menuBarBackground, options: MenuBarBackground.allCases, label: \.label)
            SettingsToggleRow(title: "Like button", isOn: $preferences.showLikeButton)
            SettingsToggleRow(title: "Lyrics button (while lyrics are off)", isOn: $preferences.showLyricsButton)
        }
    }
}

struct LyricsSettingsPage: View {
    @ObservedObject var lyrics: LyricsSession
    @ObservedObject var preferences: LyricsPreferences

    var body: some View {
        SettingsSection(title: "Lyrics") {
            SettingsToggleRow(title: "Show lyrics below the menu bar", isOn: $lyrics.isEnabled)
            if !lyrics.statusText.isEmpty {
                Text(lyrics.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        SettingsSection(title: "Look") {
            SettingsPickerRow(title: "Style", selection: $preferences.pillStyle, options: LyricsPillStyle.allCases, segmented: true, label: \.label)
            SettingsPickerRow(
                title: "Lines",
                hint: LyricsLineCount.description(preferences.visibleLineCount),
                selection: $preferences.visibleLineCount,
                options: LyricsTimeline.lineCountOptions,
                segmented: true,
                label: { "\($0)" }
            )
        }
        SettingsSection(title: "Timing and position") {
            HStack {
                SettingsRowTitle(title: "Timing", hint: "Higher shows lines earlier")
                Spacer()
                Text(String(format: "%+.1f s", preferences.timingOffset))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("Timing", value: $preferences.timingOffset, in: LyricsPreferences.timingOffsetRange, step: 0.1)
                    .labelsHidden()
                    .pointingHandCursor()
            }
            HStack {
                SettingsPickerRow(
                    title: "Position",
                    hint: "Where reset puts them",
                    selection: $preferences.defaultPosition,
                    options: LyricsDefaultPosition.allCases,
                    label: \.label
                )
                Button("Reset", action: preferences.resetPosition)
                    .pointingHandCursor()
            }
        }
    }
}

/// Name and version at the bottom of the General page.
struct AboutFooter: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("\(AppInfo.name) \(AppInfo.version)")
                .font(.caption.weight(.semibold))
            Text("Not affiliated with Spotify")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
