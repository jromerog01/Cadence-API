import AVFoundation
import Foundation
import Observation

@MainActor @Observable final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var isPaused = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var recordedFileURL: URL?
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var destinationURL: URL?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async {
        guard await requestPermission() else {
            errorMessage = "Se requiere permiso para usar el micrófono."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "ImportedAudio/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let filename = "Grabación \(formatter.string(from: Date())).m4a"
            let fileURL = folder.appending(path: filename)
            destinationURL = fileURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                throw LocalSpeechError.audioFormat
            }

            recorder = newRecorder
            isRecording = true
            isPaused = false
            elapsedTime = 0
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        stopTimer()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        isPaused = false
        startTimer()
    }

    func stop() -> URL? {
        guard isRecording || isPaused else { return recordedFileURL }
        stopTimer()
        recorder?.stop()
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recordedFileURL = destinationURL
        return destinationURL
    }

    func cancel() {
        stopTimer()
        recorder?.stop()
        if let url = destinationURL {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        isPaused = false
        destinationURL = nil
        recordedFileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (power + 60) / 60))
                self.audioLevel = normalized
                self.elapsedTime = rec.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            pause()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.errorMessage = "La grabación finalizó con errores"
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
