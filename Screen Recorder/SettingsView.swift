import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            // Video name prefix
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Name Prefix")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. Recording, MyVideo, Screen", text: $settings.filePrefix)
                    .textFieldStyle(.roundedBorder)
                Text("Files will be named: \(settings.filePrefix.isEmpty ? "Recording" : settings.filePrefix)-2026-04-01-120000.mp4")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Save directory
            VStack(alignment: .leading, spacing: 4) {
                Text("Save Location")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(settings.saveDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Change...") {
                        SettingsManager.shared.promptForDirectory()
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            }

            Spacer()

            // Save button
            HStack {
                Spacer()
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 450, height: 240)
    }
}
