@testable import AppDomain
import Foundation
import Testing

struct SRGBColorTests {
    @Test func parsesExactlySixHexDigits() {
        #expect(SRGBColor(hex: "1ED760") == SRGBColor(red: 0x1E, green: 0xD7, blue: 0x60))
        #expect(SRGBColor(hex: "1ed760")?.hex == "1ED760")
        #expect(SRGBColor(hex: "1ED76") == nil)
        #expect(SRGBColor(hex: "+1ED76") == nil)
        #expect(SRGBColor(hex: "GGGGGG") == nil)
    }

    @Test func acceptsWhatPeopleType() {
        #expect(SRGBColor(typed: "#ff8800")?.hex == "FF8800")
        #expect(SRGBColor(typed: "FF 88 00")?.hex == "FF8800")
        #expect(SRGBColor(typed: "#ff88") == nil)
    }

    @Test func clampsChannels() {
        var colour = SRGBColor(red: 300, green: -5, blue: 10)
        #expect(colour == SRGBColor(red: 255, green: 0, blue: 10))
        colour[.blue] = 999
        #expect(colour.blue == 255)
    }

    @Test func convertsToHueSaturationBrightness() {
        let red = SRGBColor(red: 255, green: 0, blue: 0).hsb
        #expect(red == HSBColor(hue: 0, saturation: 1, brightness: 1))
        let blue = SRGBColor(red: 0, green: 0, blue: 255).hsb
        #expect(abs(blue.hue - 2.0 / 3) < 0.0001)
        let grey = SRGBColor(red: 128, green: 128, blue: 128).hsb
        #expect(grey.saturation == 0)
    }
}

struct AppearanceOptionsTests {
    private let track = Track(title: "Harder, Better, Faster, Stronger", artist: "Daft Punk", album: "", uri: "", duration: 0)

    @Test func writesTheMenuBarText() {
        #expect(MenuBarTextStyle.artistTitle.text(for: track, maxLength: 80) == "Daft Punk – Harder, Better, Faster, Stronger")
        #expect(MenuBarTextStyle.titleOnly.text(for: track, maxLength: 80) == track.title)
        #expect(MenuBarTextStyle.hidden.text(for: track, maxLength: 80) == nil)
    }

    @Test func shortensLongText() {
        let text = MenuBarTextStyle.titleArtist.text(for: track, maxLength: 15)
        #expect(text == "Harder, Better…")
        #expect(text?.count == 15)
    }

    @Test func readsVisualizerNamesFromEarlierVersions() {
        #expect(VisualizerStyle(storedValue: "waveLine") == .oscilloscope)
        #expect(VisualizerStyle(storedValue: "warp") == nil) // retired visuals fall back to the default
        #expect(VisualizerStyle(storedValue: "waveCircle") == nil)
        #expect(VisualizerStyle(storedValue: "analyzer") == .analyzer)
        #expect(VisualizerStyle(storedValue: "bars") == nil)
        #expect(VisualizerStyle(storedValue: "speaker") == nil)
        #expect(VisualizerStyle(storedValue: "unknown") == nil)
    }

    @Test func cyclesThroughEveryVisual() {
        var style = VisualizerStyle.allCases[0]
        var seen: [VisualizerStyle] = []
        for _ in VisualizerStyle.allCases {
            seen.append(style)
            style = style.next
        }
        #expect(seen == VisualizerStyle.allCases)
        #expect(style == VisualizerStyle.allCases[0])
    }

    @Test func stepsBackWithWraparound() {
        #expect(VisualizerStyle.analyzer.previous == VisualizerStyle.allCases.last)
        #expect(VisualizerStyle.spectrogram.previous == .analyzer)
        #expect(VisualizerStyle.chromagram.next.previous == .chromagram)
    }
}

@MainActor
struct PreferencesTests {
    @Test func startsWithTheDefaults() {
        let preferences = Preferences(storage: InMemorySettingsStorage())
        #expect(preferences.menuBarTextStyle == .artistTitle)
        #expect(preferences.maxTextLength == 40)
        #expect(preferences.showVisualizer)
        #expect(!preferences.compactPlayer)
        #expect(preferences.isDefaultAccent)
    }

    @Test func keepsChangesBetweenLaunches() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)
        preferences.menuBarBackground = .album
        preferences.setAccent(.red, to: 255)
        preferences.visualizerStyle = .vectorscope

        let relaunched = Preferences(storage: storage)
        #expect(relaunched.menuBarBackground == .album)
        #expect(relaunched.accentColor.hex == "FFD760")
        #expect(relaunched.visualizerStyle == .vectorscope)
    }

    @Test func ignoresAnInvalidSavedAccent() {
        let storage = InMemorySettingsStorage()
        storage.values["accentHex"] = "nonsense"
        #expect(Preferences(storage: storage).accentColor == Preferences.defaultAccent)
    }

    @Test func resetsTheAccent() {
        let preferences = Preferences(storage: InMemorySettingsStorage())
        preferences.accentColor = SRGBColor(red: 1, green: 2, blue: 3)
        preferences.resetAccent()
        #expect(preferences.isDefaultAccent)
    }
}

struct AlbumPaletteTests {
    private func pixels(_ colours: [(UInt8, UInt8, UInt8, count: Int)]) -> [UInt8] {
        colours.flatMap { colour in Array(repeating: [colour.0, colour.1, colour.2, 255], count: colour.count).flatMap { $0 } }
    }

    @Test func picksTheMainColourAndAClearlyDifferentOne() throws {
        let palette = try #require(AlbumPalette.extract(fromRGBA: pixels([(220, 30, 30, count: 700), (30, 30, 220, count: 324)])))
        #expect(palette.primary.hue < 0.05) // red
        #expect(abs(palette.secondary.hue - 2.0 / 3) < 0.05) // blue
    }

    @Test func darkensColoursForWhiteText() throws {
        let palette = try #require(AlbumPalette.extract(fromRGBA: pixels([(250, 250, 120, count: 1024)])))
        #expect(palette.primary.brightness <= 0.55)
        #expect(palette.secondary.brightness <= 0.4)
    }

    @Test func needsPixels() {
        #expect(AlbumPalette.extract(fromRGBA: []) == nil)
    }
}
