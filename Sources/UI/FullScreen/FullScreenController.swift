import AppKit
import SwiftUI

/// Shows `FullScreenView` in its own full-screen space, and tidies up when it's left
/// (Esc, the close button, or the usual full-screen controls).
@MainActor
final class FullScreenController: NSObject, NSWindowDelegate {
    private let models: AppModels
    private var window: NSWindow?
    /// Called when the view appears or goes away, so audio capture can follow.
    var onVisibilityChange: () -> Void = {}

    init(models: AppModels) {
        self.models = models
    }

    var isShown: Bool { window != nil }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let window = NSWindow(
            contentRect: screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: FullScreenView(models: models) { [weak self] in self?.close() })
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        onVisibilityChange()
    }

    func close() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil) // finishes in windowDidExitFullScreen
        } else {
            window.close()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        onVisibilityChange()
    }
}
