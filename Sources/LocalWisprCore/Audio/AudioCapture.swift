import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var audioFile: AVAudioFile?
    private var rawURL: URL?
    private var startedAt: Date?
    private var chunkWriter: AudioChunkWriter?
    private var chunkHandler: (@Sendable (AudioChunk) -> Void)?

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

    func start(
        chunking: AudioChunkingConfiguration? = nil,
        onChunkFinalized: (@Sendable (AudioChunk) -> Void)? = nil
    ) throws {
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
        let startedAt = Date()
        let rawURL = directory.appendingPathComponent("\(id).caf")
        let audioFile = try AVAudioFile(forWriting: rawURL, settings: inputFormat.settings)
        let chunkWriter = try chunking.map {
            try AudioChunkWriter(
                directory: directory,
                sessionID: id,
                inputFormat: inputFormat,
                startedAt: startedAt,
                configuration: $0
            )
        }

        lock.withLock {
            self.audioFile = audioFile
            self.rawURL = rawURL
            self.startedAt = startedAt
            self.chunkWriter = chunkWriter
            self.chunkHandler = onChunkFinalized
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.write(buffer, receivedAt: Date())
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()

            let urls = lock.withLock {
                let urls = [self.rawURL].compactMap { $0 } + (self.chunkWriter?.temporaryURLs ?? [])
                self.audioFile = nil
                self.rawURL = nil
                self.startedAt = nil
                self.chunkWriter = nil
                self.chunkHandler = nil
                return urls
            }

            Self.removeFiles(urls)
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
            let chunkFinish = chunkWriter?.finish(endedAt: endedAt)
            let state = (
                rawURL: rawURL,
                startedAt: startedAt,
                pendingChunks: chunkFinish?.pendingChunks ?? [],
                expectedStreamingChunkCount: chunkFinish?.expectedChunkCount
            )
            audioFile = nil
            rawURL = nil
            startedAt = nil
            chunkWriter = nil
            chunkHandler = nil
            return state
        }

        guard let rawURL = state.rawURL, let startedAt = state.startedAt else {
            throw LocalWisprError.recordingNotActive
        }

        let wavURL = rawURL.deletingPathExtension().appendingPathExtension("wav")
        do {
            try Self.convertToWhisperReadyWav(rawURL: rawURL, wavURL: wavURL)
        } catch {
            Self.removeFiles([rawURL, wavURL])
            throw error
        }

        let chunks = state.pendingChunks.compactMap { pendingChunk in
            do {
                return try Self.convertPendingChunk(pendingChunk)
            } catch {
                NSLog("LocalWispr failed to finalize streaming audio chunk: \(error.localizedDescription)")
                Self.removeFiles([pendingChunk.rawURL, pendingChunk.wavURL])
                return nil
            }
        }

        return AudioRecording(
            rawURL: rawURL,
            wavURL: wavURL,
            startedAt: startedAt,
            endedAt: endedAt,
            chunks: chunks,
            expectedStreamingChunkCount: state.expectedStreamingChunkCount
        )
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let urls = lock.withLock {
            let urls = [rawURL].compactMap { $0 } + (chunkWriter?.temporaryURLs ?? [])
            audioFile = nil
            rawURL = nil
            startedAt = nil
            chunkWriter = nil
            chunkHandler = nil
            return urls
        }

        Self.removeFiles(urls)
    }

    private func write(_ buffer: AVAudioPCMBuffer, receivedAt: Date) {
        let result = lock.withLock { () -> (pendingChunks: [PendingAudioChunk], handler: (@Sendable (AudioChunk) -> Void)?, cleanupURLs: [URL]) in
            do {
                try audioFile?.write(from: buffer)
            } catch {
                NSLog("LocalWispr failed to write audio buffer: \(error.localizedDescription)")
            }

            do {
                let pendingChunks = try chunkWriter?.write(buffer, receivedAt: receivedAt) ?? []
                return (pendingChunks, chunkHandler, [])
            } catch {
                NSLog("LocalWispr failed to write streaming audio chunk: \(error.localizedDescription)")
                let cleanupURLs = chunkWriter?.temporaryURLs ?? []
                chunkWriter = nil
                chunkHandler = nil
                return ([], nil, cleanupURLs)
            }
        }

        Self.removeFiles(result.cleanupURLs)
        guard let handler = result.handler else { return }

        for pendingChunk in result.pendingChunks {
            Self.deliverPendingChunk(pendingChunk, handler: handler)
        }
    }

    private static func deliverPendingChunk(
        _ pendingChunk: PendingAudioChunk,
        handler: @escaping @Sendable (AudioChunk) -> Void
    ) {
        Task.detached(priority: .utility) {
            do {
                let chunk = try convertPendingChunk(pendingChunk)
                handler(chunk)
            } catch {
                NSLog("LocalWispr failed to finalize streaming audio chunk: \(error.localizedDescription)")
                removeFiles([pendingChunk.rawURL, pendingChunk.wavURL])
            }
        }
    }

    private static func convertPendingChunk(_ pendingChunk: PendingAudioChunk) throws -> AudioChunk {
        let wavURL = pendingChunk.wavURL
        do {
            try convertToWhisperReadyWav(rawURL: pendingChunk.rawURL, wavURL: wavURL)
        } catch {
            removeFiles([pendingChunk.rawURL, wavURL])
            throw error
        }

        return AudioChunk(
            index: pendingChunk.index,
            rawURL: pendingChunk.rawURL,
            wavURL: wavURL,
            startedAt: pendingChunk.startedAt,
            endedAt: pendingChunk.endedAt
        )
    }

    private static func removeFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
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

private struct PendingAudioChunk: Sendable, Equatable {
    let index: Int
    let rawURL: URL
    let startedAt: Date
    let endedAt: Date

    var wavURL: URL {
        rawURL.deletingPathExtension().appendingPathExtension("wav")
    }
}

private struct AudioChunkWriterFinish {
    let pendingChunks: [PendingAudioChunk]
    let expectedChunkCount: Int
}

private final class AudioChunkWriter {
    private let directory: URL
    private let sessionID: String
    private let inputFormat: AVAudioFormat
    private let targetFrameCount: AVAudioFramePosition

    private var currentFile: AVAudioFile?
    private var currentRawURL: URL?
    private var currentStartedAt: Date
    private var currentFrameCount: AVAudioFramePosition = 0
    private var currentIndex = 0

    init(
        directory: URL,
        sessionID: String,
        inputFormat: AVAudioFormat,
        startedAt: Date,
        configuration: AudioChunkingConfiguration
    ) throws {
        self.directory = directory
        self.sessionID = sessionID
        self.inputFormat = inputFormat
        self.currentStartedAt = startedAt
        self.targetFrameCount = max(
            1,
            AVAudioFramePosition(configuration.chunkDuration * inputFormat.sampleRate)
        )

        try startNewChunk(index: 0)
    }

    var temporaryURLs: [URL] {
        [currentRawURL].compactMap { $0 }
    }

    func write(_ buffer: AVAudioPCMBuffer, receivedAt: Date) throws -> [PendingAudioChunk] {
        guard buffer.frameLength > 0 else { return [] }

        try currentFile?.write(from: buffer)
        currentFrameCount += AVAudioFramePosition(buffer.frameLength)

        guard currentFrameCount >= targetFrameCount else { return [] }
        return [try rotate(endedAt: estimatedEndDate(fallback: receivedAt))]
    }

    func finish(endedAt: Date) -> AudioChunkWriterFinish {
        currentFile = nil

        guard let currentRawURL else {
            return AudioChunkWriterFinish(pendingChunks: [], expectedChunkCount: currentIndex)
        }

        guard currentFrameCount > 0 else {
            try? FileManager.default.removeItem(at: currentRawURL)
            self.currentRawURL = nil
            return AudioChunkWriterFinish(pendingChunks: [], expectedChunkCount: currentIndex)
        }

        let pendingChunk = PendingAudioChunk(
            index: currentIndex,
            rawURL: currentRawURL,
            startedAt: currentStartedAt,
            endedAt: maxDate(estimatedEndDate(fallback: endedAt), currentStartedAt)
        )
        self.currentRawURL = nil

        return AudioChunkWriterFinish(
            pendingChunks: [pendingChunk],
            expectedChunkCount: currentIndex + 1
        )
    }

    private func rotate(endedAt: Date) throws -> PendingAudioChunk {
        currentFile = nil

        guard let currentRawURL else {
            throw LocalWisprError.audioConversionFailed("missing streaming chunk file")
        }

        let pendingChunk = PendingAudioChunk(
            index: currentIndex,
            rawURL: currentRawURL,
            startedAt: currentStartedAt,
            endedAt: maxDate(endedAt, currentStartedAt)
        )

        currentIndex += 1
        currentStartedAt = pendingChunk.endedAt
        currentFrameCount = 0
        self.currentRawURL = nil
        try startNewChunk(index: currentIndex)

        return pendingChunk
    }

    private func startNewChunk(index: Int) throws {
        let url = directory.appendingPathComponent("\(sessionID)-chunk-\(index).caf")
        currentRawURL = url
        currentFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)
    }

    private func estimatedEndDate(fallback: Date) -> Date {
        guard inputFormat.sampleRate > 0 else { return fallback }
        return currentStartedAt.addingTimeInterval(Double(currentFrameCount) / inputFormat.sampleRate)
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs >= rhs ? lhs : rhs
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
