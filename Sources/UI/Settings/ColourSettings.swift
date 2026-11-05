import AppDomain
import SwiftUI

/// The accent colour: hex field, reset to Spotify green, and a slider per channel.
struct ColourSettings: View {
    @ObservedObject var preferences: Preferences
    @State private var hexDraft = ""

    var body: some View {
        SettingsSection(title: "Accent colour") {
            HStack {
                Text("Accent")
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(preferences.accentColor))
                    .frame(width: 28, height: 16)
                TextField("RRGGBB", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 70)
                    .onSubmit(applyHexDraft)
                    .onAppear { hexDraft = preferences.accentColor.hex }
                    .onChange(of: preferences.accentColor) { hexDraft = $0.hex }
                Button("Reset", action: preferences.resetAccent)
                    .disabled(preferences.isDefaultAccent)
                    .help("Back to Spotify green")
                    .pointingHandCursor()
            }
            channelSlider("R", channel: .red, tint: .red)
            channelSlider("G", channel: .green, tint: .green)
            channelSlider("B", channel: .blue, tint: .blue)
        }
    }

    private func channelSlider(_ label: String, channel: SRGBColor.Channel, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Slider(
                value: Binding(
                    get: { Double(preferences.accentColor[channel]) },
                    set: { preferences.setAccent(channel, to: Int($0.rounded())) }
                ),
                in: 0...255
            )
            .tint(tint)
            .pointingHandCursor()
            Text("\(preferences.accentColor[channel])")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    /// Takes "#FF8800" or "ff8800"; anything else snaps back to the current colour.
    private func applyHexDraft() {
        if let colour = SRGBColor(typed: hexDraft) {
            preferences.accentColor = colour
        } else {
            hexDraft = preferences.accentColor.hex
        }
    }
}
