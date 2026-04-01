import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("saveDirectory") var saveDirectory: String = SettingsManager.defaultDirectory
    @AppStorage("hasChosenDirectory") var hasChosenDirectory: Bool = false
    @AppStorage("filePrefix") var filePrefix: String = "Recording"

    static var defaultDirectory: String {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!.path
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectory)
    }

    /// Shows an NSOpenPanel to pick a save directory. Returns true if user picked one, false if cancelled.
    @discardableResult
    func promptForDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save recordings"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url.path
            hasChosenDirectory = true
            return true
        }
        return false
    }
}
