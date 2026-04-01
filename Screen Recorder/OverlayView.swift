import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var recorder: ScreenRecorder

    var body: some View {
        VStack(spacing: 6) {
            // Toast
            if recorder.showSavedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved: \(recorder.savedFilePath)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Controls
            HStack(spacing: 12) {
                // Time display
                Text(formatTime(recorder.elapsedTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 70, alignment: .leading)

                Divider()
                    .frame(height: 20)

                // Settings button
                Button(action: {
                    AppDelegate.shared?.openSettings()
                }) {
                    Image(systemName: "gear")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Settings")

                Divider()
                    .frame(height: 20)

                switch recorder.state {
                case .idle:
                    Button(action: { recorder.startRecording() }) {
                        Image(systemName: "record.circle")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Start Recording")

                case .recording:
                    Button(action: { recorder.pauseRecording() }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title2)
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("Pause Recording")

                    Button(action: { recorder.stopRecording() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Recording")

                case .paused:
                    Button(action: { recorder.resumeRecording() }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Resume Recording")

                    Button(action: { recorder.stopRecording() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Recording")

                case .saving:
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
        }
        .animation(.easeInOut(duration: 0.3), value: recorder.showSavedToast)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int(time * 10) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
