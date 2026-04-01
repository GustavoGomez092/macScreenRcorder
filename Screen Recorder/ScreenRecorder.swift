import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

enum RecordingState {
    case idle, recording, paused, saving
}

class ScreenRecorder: NSObject, ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var showSavedToast = false
    @Published var savedFilePath: String = ""

    var overlayWindowID: CGWindowID?

    // Capture
    private var stream: SCStream?
    private var captureSession: AVCaptureSession?

    // Writer
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Timing state — all accessed only on writerQueue
    private var isWriterStarted = false
    private var sessionStartTime: CMTime = .zero  // PTS of the very first sample
    private var outputTime: CMTime = .zero         // running output clock
    private var lastInputTime: CMTime = .zero      // last PTS we saw before pause
    private var isPaused = false
    private var needsResync = false                 // true after resume, resync on next sample

    private let writerQueue = DispatchQueue(label: "com.screenrecorder.writer")

    // Timer
    private var timerCancellable: AnyCancellable?
    private var recordingStartDate: Date?
    private var pausedAccumulatedTime: TimeInterval = 0

    // MARK: - Public API

    func startRecording() {
        guard state == .idle else { return }

        if !SettingsManager.shared.hasChosenDirectory {
            guard SettingsManager.shared.promptForDirectory() else { return }
        }

        Task {
            do {
                // Request microphone if needed (no dialog loop, just a one-time prompt)
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    await AVCaptureDevice.requestAccess(for: .audio)
                }

                // Get available screen content — system handles permission prompt automatically
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let excludedWindows = content.windows.filter { [weak self] window in
                    guard let overlayID = self?.overlayWindowID else { return false }
                    return window.windowID == overlayID
                }
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

                let config = SCStreamConfiguration()
                let videoWidth = display.width * 2
                let videoHeight = display.height * 2
                config.width = videoWidth
                config.height = videoHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.showsCursor = true
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let prefix = SettingsManager.shared.filePrefix.isEmpty ? "Recording" : SettingsManager.shared.filePrefix
                let filename = "\(prefix)-\(dateFormatter.string(from: Date())).mp4"
                let saveDir = SettingsManager.shared.saveDirectoryURL
                try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                let outputURL = saveDir.appendingPathComponent(filename)

                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: videoWidth,
                    AVVideoHeightKey: videoHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 8_000_000,
                        AVVideoExpectedSourceFrameRateKey: 60,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                ]
                let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                vInput.expectsMediaDataInRealTime = true

                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: vInput,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: videoWidth,
                        kCVPixelBufferHeightKey as String: videoHeight
                    ]
                )
                writer.add(vInput)

                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                aInput.expectsMediaDataInRealTime = true
                writer.add(aInput)

                self.assetWriter = writer
                self.videoInput = vInput
                self.audioInput = aInput
                self.pixelBufferAdaptor = adaptor
                self.isWriterStarted = false
                self.sessionStartTime = .zero
                self.outputTime = .zero
                self.lastInputTime = .zero
                self.isPaused = false
                self.needsResync = false

                // Microphone
                let session = AVCaptureSession()
                guard let mic = AVCaptureDevice.default(for: .audio) else { return }
                let micInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(micInput) { session.addInput(micInput) }

                let audioOutput = AVCaptureAudioDataOutput()
                audioOutput.setSampleBufferDelegate(self, queue: writerQueue)
                if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
                self.captureSession = session

                let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
                try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writerQueue)
                self.stream = scStream

                do {
                    try await scStream.startCapture()
                } catch let error as NSError where error.code == -3801 {
                    // Permission not granted — clean up and show alert
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    self.pixelBufferAdaptor = nil
                    self.stream = nil

                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Screen Recording Permission Required"
                        alert.informativeText = "Grant permission in System Settings, then quit and relaunch REC.\n\n1. Toggle REC ON in the list\n2. Quit REC completely\n3. Relaunch REC"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Open System Settings")
                        alert.addButton(withTitle: "OK")
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                    return
                }

                session.startRunning()

                await MainActor.run {
                    self.state = .recording
                    self.recordingStartDate = Date()
                    self.pausedAccumulatedTime = 0
                    self.startTimer()
                }

            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        writerQueue.sync { self.isPaused = true }
        state = .paused
        pausedAccumulatedTime = elapsedTime
        stopTimer()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        writerQueue.sync {
            self.isPaused = false
            self.needsResync = true
        }
        state = .recording
        recordingStartDate = Date()
        startTimer()
    }

    func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .saving
        stopTimer()

        // Tell writer queue to stop accepting
        writerQueue.sync { self.isPaused = true }

        Task {
            try? await stream?.stopCapture()
            stream = nil

            await MainActor.run {
                self.captureSession?.stopRunning()
                self.captureSession = nil
            }

            let writer = self.assetWriter
            let vInput = self.videoInput
            let aInput = self.audioInput
            let outputPath = writer?.outputURL.lastPathComponent ?? ""

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writerQueue.async {
                    vInput?.markAsFinished()
                    aInput?.markAsFinished()
                    continuation.resume()
                }
            }

            if writer?.status == .writing {
                await writer?.finishWriting()
            }

            let success = writer?.status == .completed
            if let error = writer?.error {
                print("Writer error: \(error)")
            }

            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.pixelBufferAdaptor = nil
            self.isWriterStarted = false

            await MainActor.run {
                self.elapsedTime = 0
                self.state = .idle
                if success {
                    self.savedFilePath = outputPath
                    self.showSavedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.showSavedToast = false
                    }
                }
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.recordingStartDate else { return }
                self.elapsedTime = self.pausedAccumulatedTime + Date().timeIntervalSince(start)
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Timestamp mapping (writerQueue only)
    //
    // Instead of subtracting accumulated pause duration (fragile with two streams),
    // we maintain a simple output clock:
    //   - outputTime tracks where we are in the output file
    //   - On each sample we compute the delta from the previous input PTS
    //   - We add that delta to outputTime
    //   - On resume (needsResync), we skip the delta (it would be the pause gap)

    private func mapTimestamp(_ inputPTS: CMTime) -> CMTime {
        if !isWriterStarted {
            // First ever sample
            sessionStartTime = inputPTS
            lastInputTime = inputPTS
            outputTime = .zero
            return .zero
        }

        if needsResync {
            // First sample after resume — don't advance outputTime
            needsResync = false
            lastInputTime = inputPTS
            return outputTime
        }

        let delta = CMTimeSubtract(inputPTS, lastInputTime)
        // Only advance if delta is positive and reasonable (< 1 second)
        if delta.seconds > 0 && delta.seconds < 1.0 {
            outputTime = CMTimeAdd(outputTime, delta)
        }
        lastInputTime = inputPTS
        return outputTime
    }

    // MARK: - Video Processing (writerQueue)

    private func processVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard !isPaused else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let outPTS = mapTimestamp(pts)

        if !isWriterStarted {
            guard assetWriter?.status != .failed else { return }
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)
            isWriterStarted = true
        }

        guard assetWriter?.status == .writing else { return }

        if videoInput?.isReadyForMoreMediaData == true {
            pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: outPTS)
        }
    }

    // MARK: - Audio Processing (writerQueue)

    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard !isPaused else { return }
        guard isWriterStarted, assetWriter?.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }

        let outPTS = mapTimestamp(pts)

        guard let adjusted = createAdjustedBuffer(from: sampleBuffer, newPTS: outPTS) else { return }

        if audioInput?.isReadyForMoreMediaData == true {
            audioInput?.append(adjusted)
        }
    }

    private func createAdjustedBuffer(from sampleBuffer: CMSampleBuffer, newPTS: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var adjustedBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedBuffer
        )
        return status == noErr ? adjustedBuffer : nil
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: statusValue),
              frameStatus == .complete else { return }
        processVideoBuffer(sampleBuffer)
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension ScreenRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processAudioBuffer(sampleBuffer)
    }
}
