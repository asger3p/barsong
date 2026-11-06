import AppDomain
import AppKit
import SwiftUI

/// Connecting a Spotify account for Liked Songs, as a guided setup: create a Spotify app
/// with the values shown, paste its Client ID (it connects by itself), approve in the browser.
/// Step 3 also has a Connect button, for when that automatic attempt didn't happen or failed.
struct AccountSettings: View {
    @ObservedObject var account: SpotifyAccount

    var body: some View {
        Group {
            if account.isConnected {
                connected
            } else if account.isConnecting {
                waitingForBrowser
            } else {
                setupSteps
            }
        }
        if let error = account.lastError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connected: some View {
        HStack {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Disconnect", action: account.disconnect)
                .pointingHandCursor()
        }
    }

    private var waitingForBrowser: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Approve \(AppInfo.name) in your browser…")
                Spacer()
                Button("Cancel", action: account.cancelConnecting)
                    .pointingHandCursor()
            }
            Text("If Spotify says “Invalid redirect URI”, add the redirect URI from step 1 to your app and try again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Like songs and open artists and albums. Spotify needs a small app of your own for this (free, takes a minute).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SetupStep(number: 1, title: "Create a Spotify app") {
                Button {
                    NSWorkspace.shared.open(SpotifyDashboard.createAppURL)
                } label: {
                    Label("Open Spotify dashboard", systemImage: "arrow.up.right.square")
                }
                .pointingHandCursor()
                CopyableValue(label: "App name", value: AppInfo.name)
                CopyableValue(label: "Redirect URI", value: account.redirectURI)
                Text("Tick **Web API**, agree and save. The account creating it needs Spotify Premium.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetupStep(number: 2, title: "Paste its Client ID") {
                HStack(spacing: 6) {
                    TextField("Client ID", text: $account.clientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .onSubmit { Task { await account.connect() } }
                    Button("Paste", action: pasteClientID)
                        .help("Paste from the clipboard")
                        .pointingHandCursor()
                }
                Text("Find it under your app's **Settings** on the dashboard. Barsong connects as soon as it's pasted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: account.clientID) { _ in
                Task { await account.connectIfClientIDLooksComplete() }
            }

            SetupStep(number: 3, title: "Approve in the browser") {
                Button("Connect") {
                    Task { await account.connect() }
                }
                .disabled(!hasClientID)
                .pointingHandCursor()
                Text("Opens Spotify in your browser to approve \(AppInfo.name). It starts by itself once the Client ID is in; this button is for trying again.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasClientID: Bool {
        !account.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pasteClientID() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        account.clientID = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SpotifyDashboard {
    static let createAppURL = URL(string: "https://developer.spotify.com/dashboard/create")!
}

/// A numbered step with its content indented under the title.
private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.secondary))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.callout.weight(.semibold))
                content
            }
        }
    }
}

/// A value to type into Spotify's form, with a copy button that confirms with a check mark.
private struct CopyableValue: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied" : "Copy")
            .pointingHandCursor()
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
