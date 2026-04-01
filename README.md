# REC

A minimal native macOS screen recorder. Records your screen and microphone simultaneously and exports to MP4.

## Features

- **Screen + Microphone recording** — captures your display at 60fps Retina resolution with microphone audio
- **MP4 export** — H.264 video + AAC audio, compatible with all players
- **Floating overlay** — always-on-top control panel with Record, Pause, Resume, and Stop buttons
- **Pause/Resume** — seamlessly pause and resume without breaking the output file
- **Settings** — configurable save directory and filename prefix
- **Saving indicator** — spinner while encoding, toast notification on completion

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (to build from source)

## Installation

### From DMG

1. Download `REC.dmg` from [Releases](https://github.com/GustavoGomez092/macScreenRcorder/releases)
2. Open the DMG and drag **REC** to Applications
3. Launch REC
4. Grant Screen Recording and Microphone permissions when prompted
5. **Restart REC** after granting Screen Recording permission (macOS requirement)

### Build from Source

```bash
git clone git@github.com:GustavoGomez092/macScreenRcorder.git
cd macScreenRcorder
open "Screen Recorder.xcodeproj"
```

In Xcode:
1. Select your development team in **Signing & Capabilities**
2. Press **Cmd+R** to build and run

## Usage

1. **Record** — click the red circle button to start recording
2. **Pause/Resume** — click pause to temporarily stop, play to resume
3. **Stop** — click the stop button to finish and save the MP4
4. **Settings** — click the gear icon to change save location and filename prefix

## Permissions

REC requires two macOS permissions:

| Permission | Why |
|---|---|
| **Screen Recording** | To capture your display |
| **Microphone** | To record audio |

After granting Screen Recording permission, you must **quit and relaunch** the app for it to take effect. This is a macOS system requirement.

## Tech Stack

- **ScreenCaptureKit** — screen capture
- **AVFoundation** — microphone capture + MP4 encoding (AVAssetWriter)
- **SwiftUI** — overlay and settings UI
- **AppKit** — floating NSPanel overlay

## Project Structure

```
Screen Recorder/
  ScreenRecorderApp.swift   — App entry point
  AppDelegate.swift         — Floating panel + settings window management
  ScreenRecorder.swift      — Core recording engine
  OverlayView.swift         — Record/Pause/Stop controls
  SettingsView.swift        — Save directory + filename prefix
  SettingsManager.swift     — UserDefaults persistence
  Info.plist                — Microphone usage description
```

## License

MIT
