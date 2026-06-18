import AVFoundation
import Foundation

enum FullSessionWavConversion: Sendable, Equatable {
    case synchronous
    case deferred
}

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var audioFile: AVAudioFile?
    private var rawURL: URL?
    private var startedAt: Date?
    private var chunkWriter: AudioChunkWriter?
    private var chunkHandler: (@Sendable (AudioChunk) -> Void)?
    private var audioBufferHandler: (@Sendable (StreamingAudioBuffer) -> Void)?

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
        onChunkFinalized: (@Sendable (AudioChunk) -> Void)? = nil,
        onAudioBuffer: (@Sendable (StreamingAudioBuffer) -> Void)? = nil
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
            self.audioBufferHandler = onAudioBuffer
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
                self.audioBufferHandler = nil
                return urls
            }

            Self.removeFiles(urls)
            throw error
        }
    }

    func stop(fullSessionWavConversion: FullSessionWavConversion = .synchronous) throws -> AudioRecording {
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
            audioBufferHandler = nil
            return state
        }

        guard let rawURL = state.rawURL, let startedAt = state.startedAt else {
            throw LocalWisprError.recordingNotActive
        }

        let wavURL = rawURL.deletingPathExtension().appendingPathExtension("wav")
        let fullSessionWavAvailability: AudioRecording.FullSessionWavAvailability
        switch fullSessionWavConversion {
        case .synchronous:
            do {
                try AudioFileConverter.convertToSTTReadyWav(rawURL: rawURL, wavURL: wavURL)
            } catch {
                let chunkURLs = state.pendingChunks.flatMap { [$0.rawURL, $0.wavURL] }
                Self.removeFiles([rawURL, wavURL] + chunkURLs)
                throw error
            }
            fullSessionWavAvailability = .ready
        case .deferred:
            fullSessionWavAvailability = .deferred
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
            expectedStreamingChunkCount: state.expectedStreamingChunkCount,
            fullSessionWavAvailability: fullSessionWavAvailability
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
            audioBufferHandler = nil
            return urls
        }

        Self.removeFiles(urls)
    }

    private func write(_ buffer: AVAudioPCMBuffer, receivedAt: Date) {
        let streamingBuffer = Self.streamingAudioBuffer(from: buffer, receivedAt: receivedAt)
        let result = lock.withLock { () -> (pendingChunks: [PendingAudioChunk], chunkHandler: (@Sendable (AudioChunk) -> Void)?, audioBufferHandler: (@Sendable (StreamingAudioBuffer) -> Void)?, cleanupURLs: [URL]) in
            do {
                try audioFile?.write(from: buffer)
            } catch {
                NSLog("LocalWispr failed to write audio buffer: \(error.localizedDescription)")
            }

            do {
                let pendingChunks = try chunkWriter?.write(buffer, receivedAt: receivedAt) ?? []
                return (pendingChunks, chunkHandler, audioBufferHandler, [])
            } catch {
                NSLog("LocalWispr failed to write streaming audio chunk: \(error.localizedDescription)")
                let cleanupURLs = chunkWriter?.temporaryURLs ?? []
                chunkWriter = nil
                chunkHandler = nil
                audioBufferHandler = nil
                return ([], nil, nil, cleanupURLs)
            }
        }

        Self.removeFiles(result.cleanupURLs)

        if let streamingBuffer, let audioBufferHandler = result.audioBufferHandler {
            audioBufferHandler(streamingBuffer)
        }

        guard let chunkHandler = result.chunkHandler else { return }

        for pendingChunk in result.pendingChunks {
            Self.deliverPendingChunk(pendingChunk, handler: chunkHandler)
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
        guard pendingChunk.shouldTranscribe else {
            return AudioChunk(
                index: pendingChunk.index,
                rawURL: pendingChunk.rawURL,
                wavURL: wavURL,
                startedAt: pendingChunk.startedAt,
                endedAt: pendingChunk.endedAt,
                shouldTranscribe: false,
                detectedSpeech: pendingChunk.detectedSpeech
            )
        }

        do {
            try AudioFileConverter.convertToSTTReadyWav(rawURL: pendingChunk.rawURL, wavURL: wavURL)
        } catch {
            removeFiles([pendingChunk.rawURL, wavURL])
            throw error
        }

        return AudioChunk(
            index: pendingChunk.index,
            rawURL: pendingChunk.rawURL,
            wavURL: wavURL,
            startedAt: pendingChunk.startedAt,
            endedAt: pendingChunk.endedAt,
            detectedSpeech: pendingChunk.detectedSpeech
        )
    }

    private static func streamingAudioBuffer(from buffer: AVAudioPCMBuffer, receivedAt: Date) -> StreamingAudioBuffer? {
        guard let samples = monoFloatSamples(from: buffer), !samples.isEmpty else { return nil }
        return StreamingAudioBuffer(
            samples: samples,
            sampleRate: buffer.format.sampleRate,
            receivedAt: receivedAt
        )
    }

    static func monoFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }

        if let channelData = buffer.floatChannelData {
            var output = Array(repeating: Float(0), count: frameCount)
            if buffer.format.isInterleaved {
                let samples = channelData[0]
                for frame in 0..<frameCount {
                    var sum = Float(0)
                    let base = frame * channelCount
                    for channel in 0..<channelCount {
                        sum += samples[base + channel]
                    }
                    output[frame] = sum / Float(channelCount)
                }
            } else {
                for channel in 0..<channelCount {
                    let samples = channelData[channel]
                    for frame in 0..<frameCount {
                        output[frame] += samples[frame] / Float(channelCount)
                    }
                }
            }
            return output
        }

        if let channelData = buffer.int16ChannelData {
            var output = Array(repeating: Float(0), count: frameCount)
            if buffer.format.isInterleaved {
                let samples = channelData[0]
                for frame in 0..<frameCount {
                    var sum = Float(0)
                    let base = frame * channelCount
                    for channel in 0..<channelCount {
                        sum += Float(samples[base + channel]) / Float(Int16.max)
                    }
                    output[frame] = sum / Float(channelCount)
                }
            } else {
                for channel in 0..<channelCount {
                    let samples = channelData[channel]
                    for frame in 0..<frameCount {
                        output[frame] += (Float(samples[frame]) / Float(Int16.max)) / Float(channelCount)
                    }
                }
            }
            return output
        }

        return nil
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

}

private struct PendingAudioChunk: Sendable, Equatable {
    let index: Int
    let rawURL: URL
    let startedAt: Date
    let endedAt: Date
    let shouldTranscribe: Bool
    let detectedSpeech: Bool?

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
    private let configuration: AudioChunkingConfiguration
    private var boundaryScheduler: AudioChunkBoundaryScheduler

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
        self.configuration = configuration
        self.boundaryScheduler = AudioChunkBoundaryScheduler(
            configuration: configuration,
            sampleRate: inputFormat.sampleRate
        )
        self.currentStartedAt = startedAt

        try startNewChunk(index: 0)
    }

    var temporaryURLs: [URL] {
        [currentRawURL].compactMap { $0 }
    }

    func write(_ buffer: AVAudioPCMBuffer, receivedAt: Date) throws -> [PendingAudioChunk] {
        guard buffer.frameLength > 0 else { return [] }

        try currentFile?.write(from: buffer)
        currentFrameCount += AVAudioFramePosition(buffer.frameLength)

        let decision = boundaryScheduler.record(
            frameCount: Int64(buffer.frameLength),
            rms: configuration.adaptiveChunking == nil ? nil : Self.rootMeanSquareEnergy(of: buffer)
        )
        guard decision.shouldRotate else { return [] }
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

        let detectedSpeech = boundaryScheduler.detectedSpeech
        let pendingChunk = PendingAudioChunk(
            index: currentIndex,
            rawURL: currentRawURL,
            startedAt: currentStartedAt,
            endedAt: maxDate(estimatedEndDate(fallback: endedAt), currentStartedAt),
            shouldTranscribe: shouldTranscribe(detectedSpeech: detectedSpeech),
            detectedSpeech: detectedSpeech
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

        let detectedSpeech = boundaryScheduler.detectedSpeech
        let pendingChunk = PendingAudioChunk(
            index: currentIndex,
            rawURL: currentRawURL,
            startedAt: currentStartedAt,
            endedAt: maxDate(endedAt, currentStartedAt),
            shouldTranscribe: shouldTranscribe(detectedSpeech: detectedSpeech),
            detectedSpeech: detectedSpeech
        )

        currentIndex += 1
        currentStartedAt = pendingChunk.endedAt
        currentFrameCount = 0
        boundaryScheduler.reset()
        self.currentRawURL = nil
        try startNewChunk(index: currentIndex)

        return pendingChunk
    }

    private func shouldTranscribe(detectedSpeech: Bool?) -> Bool {
        guard configuration.adaptiveChunking?.dropsSilentChunks == true else { return true }
        return detectedSpeech != false
    }

    private static func rootMeanSquareEnergy(of buffer: AVAudioPCMBuffer) -> Float? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }

        let bufferCount = buffer.format.isInterleaved ? 1 : channelCount
        let samplesPerBuffer = frameCount * (buffer.format.isInterleaved ? channelCount : 1)

        if let channelData = buffer.floatChannelData {
            var sumOfSquares = 0.0
            var sampleCount = 0
            for channel in 0..<bufferCount {
                let samples = channelData[channel]
                for frame in 0..<samplesPerBuffer {
                    let sample = Double(samples[frame])
                    sumOfSquares += sample * sample
                }
                sampleCount += samplesPerBuffer
            }
            guard sampleCount > 0 else { return nil }
            return Float((sumOfSquares / Double(sampleCount)).squareRoot())
        }

        if let channelData = buffer.int16ChannelData {
            var sumOfSquares = 0.0
            var sampleCount = 0
            for channel in 0..<bufferCount {
                let samples = channelData[channel]
                for frame in 0..<samplesPerBuffer {
                    let sample = Double(samples[frame]) / Double(Int16.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += samplesPerBuffer
            }
            guard sampleCount > 0 else { return nil }
            return Float((sumOfSquares / Double(sampleCount)).squareRoot())
        }

        return nil
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
