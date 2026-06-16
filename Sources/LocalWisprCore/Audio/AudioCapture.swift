import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var audioFile: AVAudioFile?
    private var rawURL: URL?
    private var startedAt: Date?

    static func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw LocalWisprError.microphonePermissionDenied
        }

        if engine.isRunning {
            _ = try? stop()
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw LocalWisprError.microphoneUnavailable
        }

        let directory = Self.recordingsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let rawURL = directory.appendingPathComponent("\(id).caf")
        let audioFile = try AVAudioFile(forWriting: rawURL, settings: inputFormat.settings)

        lock.withLock {
            self.audioFile = audioFile
            self.rawURL = rawURL
            self.startedAt = Date()
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.write(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()

            let urls = lock.withLock {
                let urls = [self.rawURL].compactMap { $0 }
                self.audioFile = nil
                self.rawURL = nil
                self.startedAt = nil
                return urls
            }

            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }

            throw error
        }
    }

    func stop() throws -> AudioRecording {
        let endedAt = Date()

        guard engine.isRunning || audioFile != nil else {
            throw LocalWisprError.recordingNotActive
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let state = lock.withLock {
            let state = (audioFile: audioFile, rawURL: rawURL, startedAt: startedAt)
            audioFile = nil
            rawURL = nil
            startedAt = nil
            return state
        }

        guard let rawURL = state.rawURL, let startedAt = state.startedAt else {
            throw LocalWisprError.recordingNotActive
        }

        let wavURL = rawURL.deletingPathExtension().appendingPathExtension("wav")
        do {
            try Self.convertToWhisperReadyWav(rawURL: rawURL, wavURL: wavURL)
        } catch {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: wavURL)
            throw error
        }

        return AudioRecording(
            rawURL: rawURL,
            wavURL: wavURL,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let urls = lock.withLock {
            let urls = [rawURL].compactMap { $0 }
            audioFile = nil
            rawURL = nil
            startedAt = nil
            return urls
        }

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            do {
                try audioFile?.write(from: buffer)
            } catch {
                NSLog("LocalWispr failed to write audio buffer: \(error.localizedDescription)")
            }
        }
    }

    private static func recordingsDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalWispr/Recordings", isDirectory: true)
    }

    private static func convertToWhisperReadyWav(rawURL: URL, wavURL: URL) throws {
        let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")

        guard FileManager.default.isExecutableFile(atPath: afconvert.path) else {
            throw LocalWisprError.audioConversionFailed("afconvert is unavailable")
        }

        let result = try ProcessRunner.runSync(
            executableURL: afconvert,
            arguments: [
                rawURL.path,
                wavURL.path,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1"
            ],
            timeout: 10
        )

        guard result.status == 0 else {
            throw LocalWisprError.audioConversionFailed(result.stderr)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
