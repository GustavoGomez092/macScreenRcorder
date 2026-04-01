import AppKit
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    let recorder = ScreenRecorder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupOverlayPanel()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func setupOverlayPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        let overlayView = OverlayView()
            .environmentObject(recorder)

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - panel.frame.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        recorder.overlayWindowID = CGWindowID(panel.windowNumber)
    }

    func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onSave: { [weak self] in
            self?.settingsWindow?.close()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "REC Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
