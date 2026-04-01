import SwiftUI

@main
struct ScreenRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — the overlay NSPanel is the main UI
        // Settings are managed by AppDelegate as a standalone NSWindow
        Settings {
            EmptyView()
        }
    }
}
