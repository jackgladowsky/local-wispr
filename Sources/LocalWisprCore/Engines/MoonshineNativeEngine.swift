import Foundation
@preconcurrency import MoonshineVoice

struct MoonshineNativeEngine: StreamingSTTEngine {
    let modelDirectory: URL
    let language: String
    let arch: MoonshineNativeModelArch

    private let transcriberStore: MoonshineNativeTranscriberStore

    var name: String {
        "Moonshine native \(language)/\(arch.rawValue)"
    }

    init(
        modelDirectory: URL,
        language: String = "en",
        arch: MoonshineNativeModelArch = .mediumStreaming,
        runtime: any MoonshineNativeRuntime = MoonshineVoiceRuntime()
    ) {
        self.modelDirectory = modelDirectory
        self.language = language
        self.arch = arch
        self.transcriberStore = MoonshineNativeTranscriberStore(
            modelDirectory: modelDirectory,
            arch: arch,
            runtime: runtime
        )
    }

    func preload() {
        Task {
            await transcriberStore.preload()
        }
    }

    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> MoonshineNativeEngine? {
        let requestedEngine = environment["LOCAL_WISPR_STT_ENGINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let requestedEngine, !["moonshine", "moonshine-native", "native-moonshine"].contains(requestedEngine) {
            return nil
        }

        if flag("LOCAL_WISPR_DISABLE_MOONSHINE_NATIVE", in: environment) {
            return nil
        }

        let language = environment["LOCAL_WISPR_MOONSHINE_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty ?? "en"
        let archName = environment["LOCAL_WISPR_MOONSHINE_NATIVE_ARCH"]
            ?? environment["LOCAL_WISPR_MOONSHINE_VOICE_ARCH"]
            ?? "medium-streaming"
        guard let arch = MoonshineNativeModelArch(rawValue: archName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            return nil
        }

        guard let modelDirectory = firstAvailableModelDirectory(
            language: language,
            arch: arch,
            environment: environment
        ) else {
            return nil
        }

        return MoonshineNativeEngine(modelDirectory: modelDirectory, language: language, arch: arch)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        guard let audioURL = request.audioURL else {
            throw LocalWisprError.missingAudioRecording
        }

        let wav = try MoonshineNativeWAVLoader.load(audioURL)
        let transcriber = try await transcriberStore.transcriber()
        let nativeTranscript = try await transcriber.transcribe(
            samples: wav.samples,
            sampleRate: Int32(wav.sampleRate)
        )

        return try Self.transcript(from: nativeTranscript, duration: request.duration)
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        let transcriber = try await transcriberStore.transcriber()
        let stream = try await transcriber.startStream(updateInterval: Self.streamingUpdateInterval())
        return MoonshineNativeStreamingSession(
            startedAt: startedAt,
            engineName: name,
            transcriber: transcriber,
            stream: stream
        )
    }

    static func transcript(from nativeTranscript: MoonshineNativeTranscript, duration: TimeInterval) throws -> Transcript {
        let nativeLines = nativeTranscript.lines
            .map { line in
                MoonshineNativeTranscriptLine(
                    text: TranscriptTextCleaner.cleanedTranscript(from: line.text),
                    startTime: line.startTime,
                    duration: line.duration
                )
            }
            .filter { !$0.text.isEmpty }

        let text = TranscriptTextCleaner.cleanedTranscript(
            from: nativeLines.map(\.text).joined(separator: " ")
        )
        guard !text.isEmpty else {
            throw LocalWisprError.emptyTranscript
        }

        let segments: [TranscriptSegment]
        if nativeLines.isEmpty {
            segments = [
                .init(text: text, startTime: 0, endTime: duration)
            ]
        } else {
            segments = nativeLines.map { line in
                let start = max(0, TimeInterval(line.startTime))
                let segmentDuration = max(0, TimeInterval(line.duration))
                let end = max(start, start + segmentDuration)
                return TranscriptSegment(text: line.text, startTime: start, endTime: end)
            }
        }

        return Transcript(text: text, confidence: nil, segments: segments)
    }

    static func firstAvailableModelDirectory(
        language: String,
        arch: MoonshineNativeModelArch,
        environment: [String: String]
    ) -> URL? {
        candidateModelDirectories(language: language, arch: arch, environment: environment)
            .first { arch.hasRequiredFiles(in: $0) }
    }

    static func candidateModelDirectories(
        language: String,
        arch: MoonshineNativeModelArch,
        environment: [String: String]
    ) -> [URL] {
        if let configured = environment["LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR"]
            ?? environment["LOCAL_WISPR_MOONSHINE_MODEL_DIR"]
        {
            return [URL(fileURLWithPath: configured.expandingTildeInPath, isDirectory: true)]
        }

        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent("MoonshineModels", isDirectory: true)
                    .appendingPathComponent(language, isDirectory: true)
                    .appendingPathComponent(arch.rawValue, isDirectory: true)
            )
        }

        candidates.append(
            LocalWisprPaths.moonshineDirectory
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(language, isDirectory: true)
                .appendingPathComponent(arch.rawValue, isDirectory: true)
        )

        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/moonshine_voice/download.moonshine.ai/model", isDirectory: true)
                .appendingPathComponent(arch.cachePathComponent(language: language), isDirectory: true)
        )

        return candidates
    }

    private static func streamingUpdateInterval() -> TimeInterval {
        ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_STREAM_UPDATE_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.02, $0) }
            ?? ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_STREAM_UPLOAD_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.02, $0) }
            ?? 0.10
    }

    private static func flag(_ name: String, in environment: [String: String]) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }
}

final class MoonshineNativeStreamingSession: StreamingSTTSession, @unchecked Sendable {
    let startedAt: Date
    let engineName: String

    private let transcriber: any MoonshineNativeTranscribing
    private let stream: any MoonshineNativeStreaming

    var name: String {
        "\(engineName) streaming"
    }

    init(
        startedAt: Date,
        engineName: String,
        transcriber: any MoonshineNativeTranscribing,
        stream: any MoonshineNativeStreaming
    ) {
        self.startedAt = startedAt
        self.engineName = engineName
        self.transcriber = transcriber
        self.stream = stream
    }

    func append(_ buffer: StreamingAudioBuffer) async throws {
        guard !buffer.samples.isEmpty else { return }
        guard buffer.sampleRate.isFinite, buffer.sampleRate > 0 else {
            throw LocalWisprError.audioConversionFailed("invalid streaming sample rate: \(buffer.sampleRate)")
        }

        try await stream.append(
            samples: buffer.samples,
            sampleRate: Int32(buffer.sampleRate.rounded())
        )
    }

    func finish(endedAt: Date) async throws -> Transcript {
        _ = transcriber // Hold the native transcriber for the lifetime of this stream.
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let nativeTranscript = try await stream.finish()
        return try MoonshineNativeEngine.transcript(from: nativeTranscript, duration: duration)
    }

    func cancel() async {
        await stream.cancel()
    }
}

enum MoonshineNativeModelArch: String, Sendable {
    case tiny
    case base
    case tinyStreaming = "tiny-streaming"
    case baseStreaming = "base-streaming"
    case smallStreaming = "small-streaming"
    case mediumStreaming = "medium-streaming"

    var moonshineModelArch: ModelArch {
        switch self {
        case .tiny:
            .tiny
        case .base:
            .base
        case .tinyStreaming:
            .tinyStreaming
        case .baseStreaming:
            .baseStreaming
        case .smallStreaming:
            .smallStreaming
        case .mediumStreaming:
            .mediumStreaming
        }
    }

    var requiredModelFiles: [String] {
        switch self {
        case .tiny, .base:
            ["encoder_model.ort", "decoder_model_merged.ort", "tokenizer.bin"]
        case .tinyStreaming, .baseStreaming, .smallStreaming, .mediumStreaming:
            ["adapter.ort", "cross_kv.ort", "decoder_kv.ort", "encoder.ort", "frontend.ort", "streaming_config.json", "tokenizer.bin"]
        }
    }

    func hasRequiredFiles(in directory: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        return requiredModelFiles.allSatisfy { fileName in
            fileManager.isReadableFile(atPath: directory.appendingPathComponent(fileName).path)
        }
    }

    func cachePathComponent(language: String) -> String {
        switch self {
        case .tiny, .base:
            "\(rawValue)-\(language)/quantized/\(rawValue)-\(language)"
        case .tinyStreaming, .baseStreaming, .smallStreaming, .mediumStreaming:
            "\(rawValue)-\(language)/quantized"
        }
    }
}

protocol MoonshineNativeRuntime: Sendable {
    func makeTranscriber(modelDirectory: URL, arch: MoonshineNativeModelArch) async throws -> any MoonshineNativeTranscribing
}

protocol MoonshineNativeTranscribing: Sendable {
    func transcribe(samples: [Float], sampleRate: Int32) async throws -> MoonshineNativeTranscript
    func startStream(updateInterval: TimeInterval) async throws -> any MoonshineNativeStreaming
}

protocol MoonshineNativeStreaming: Sendable {
    func append(samples: [Float], sampleRate: Int32) async throws
    func finish() async throws -> MoonshineNativeTranscript
    func cancel() async
}

actor MoonshineNativeTranscriberStore {
    private let modelDirectory: URL
    private let arch: MoonshineNativeModelArch
    private let runtime: any MoonshineNativeRuntime

    private var cachedTranscriber: (any MoonshineNativeTranscribing)?
    private var loadingTask: Task<any MoonshineNativeTranscribing, Error>?

    init(
        modelDirectory: URL,
        arch: MoonshineNativeModelArch,
        runtime: any MoonshineNativeRuntime
    ) {
        self.modelDirectory = modelDirectory
        self.arch = arch
        self.runtime = runtime
    }

    func preload() {
        _ = loadingTaskIfNeeded()
    }

    func transcriber() async throws -> any MoonshineNativeTranscribing {
        if let cachedTranscriber {
            return cachedTranscriber
        }

        let task = loadingTaskIfNeeded()
        do {
            let transcriber = try await task.value
            cachedTranscriber = transcriber
            loadingTask = nil
            return transcriber
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private func loadingTaskIfNeeded() -> Task<any MoonshineNativeTranscribing, Error> {
        if let loadingTask {
            return loadingTask
        }

        let runtime = runtime
        let modelDirectory = modelDirectory
        let arch = arch
        let task = Task<any MoonshineNativeTranscribing, Error> {
            try await runtime.makeTranscriber(modelDirectory: modelDirectory, arch: arch)
        }
        loadingTask = task
        return task
    }
}

struct MoonshineVoiceRuntime: MoonshineNativeRuntime {
    func makeTranscriber(modelDirectory: URL, arch: MoonshineNativeModelArch) async throws -> any MoonshineNativeTranscribing {
        do {
            let transcriber = try MoonshineVoice.Transcriber(
                modelPath: modelDirectory.path,
                modelArch: arch.moonshineModelArch
            )
            return MoonshineVoiceTranscriberBox(transcriber: transcriber)
        } catch {
            throw MoonshineNativeRuntimeError.operationFailed(
                operation: "load transcriber",
                detail: MoonshineNativeRuntimeError.describe(error)
            )
        }
    }
}

final class MoonshineVoiceTranscriberBox: MoonshineNativeTranscribing, @unchecked Sendable {
    private let transcriber: MoonshineVoice.Transcriber
    private let lock = NSLock()

    init(transcriber: MoonshineVoice.Transcriber) {
        self.transcriber = transcriber
    }

    func transcribe(samples: [Float], sampleRate: Int32) async throws -> MoonshineNativeTranscript {
        try lock.withLock {
            do {
                let transcript = try transcriber.transcribeWithoutStreaming(
                    audioData: samples,
                    sampleRate: sampleRate
                )
                return MoonshineNativeTranscript(transcript)
            } catch {
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "transcribe",
                    detail: MoonshineNativeRuntimeError.describe(error)
                )
            }
        }
    }

    func startStream(updateInterval: TimeInterval) async throws -> any MoonshineNativeStreaming {
        try lock.withLock {
            do {
                let stream = try transcriber.createStream(updateInterval: updateInterval)
                try stream.start()
                return MoonshineVoiceStreamBox(stream: stream, lock: lock)
            } catch {
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "start stream",
                    detail: MoonshineNativeRuntimeError.describe(error)
                )
            }
        }
    }
}

final class MoonshineVoiceStreamBox: MoonshineNativeStreaming, @unchecked Sendable {
    private let stream: MoonshineVoice.Stream
    private let lock: NSLock
    private var isFinished = false

    init(stream: MoonshineVoice.Stream, lock: NSLock) {
        self.stream = stream
        self.lock = lock
    }

    func append(samples: [Float], sampleRate: Int32) async throws {
        try lock.withLock {
            guard !isFinished else {
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "append audio",
                    detail: "streaming session is closed"
                )
            }

            do {
                try stream.addAudio(samples, sampleRate: sampleRate)
            } catch {
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "append audio",
                    detail: MoonshineNativeRuntimeError.describe(error)
                )
            }
        }
    }

    func finish() async throws -> MoonshineNativeTranscript {
        try lock.withLock {
            guard !isFinished else {
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "finish stream",
                    detail: "streaming session is already closed"
                )
            }

            isFinished = true
            do {
                try stream.stop()
                let transcript = try stream.updateTranscription(flags: TranscribeStreamFlags.flagForceUpdate)
                stream.close()
                return MoonshineNativeTranscript(transcript)
            } catch {
                stream.close()
                throw MoonshineNativeRuntimeError.operationFailed(
                    operation: "finish stream",
                    detail: MoonshineNativeRuntimeError.describe(error)
                )
            }
        }
    }

    func cancel() async {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true
            try? stream.stop()
            stream.close()
        }
    }
}

struct MoonshineNativeTranscript: Sendable, Equatable {
    let lines: [MoonshineNativeTranscriptLine]

    init(lines: [MoonshineNativeTranscriptLine]) {
        self.lines = lines
    }

    init(_ transcript: MoonshineVoice.Transcript) {
        lines = transcript.lines.map { line in
            MoonshineNativeTranscriptLine(
                text: line.text,
                startTime: line.startTime,
                duration: line.duration
            )
        }
    }
}

struct MoonshineNativeTranscriptLine: Sendable, Equatable {
    let text: String
    let startTime: Float
    let duration: Float
}

enum MoonshineNativeRuntimeError: LocalizedError, Sendable {
    case operationFailed(operation: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation, let detail):
            "Moonshine native \(operation) failed: \(detail)"
        }
    }

    static func describe(_ error: Error) -> String {
        if let moonshineError = error as? MoonshineVoice.MoonshineError {
            return moonshineError.message
        }

        return error.localizedDescription
    }
}

enum MoonshineNativeWAVLoader {
    struct WAVData: Sendable, Equatable {
        let samples: [Float]
        let sampleRate: Int
    }

    static func load(_ url: URL) throws -> WAVData {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              data.asciiString(in: 0..<4) == "RIFF",
              data.asciiString(in: 8..<12) == "WAVE"
        else {
            throw LocalWisprError.audioConversionFailed("Moonshine native expected a RIFF/WAVE file")
        }

        var offset = 12
        var audioFormat: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataRange: Range<Int>?

        while offset + 8 <= data.count {
            let chunkID = data.asciiString(in: offset..<(offset + 4))
            let chunkSize = Int(data.uint32LittleEndian(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt " {
                guard chunkSize >= 16, chunkStart + 16 <= data.count else {
                    throw LocalWisprError.audioConversionFailed("WAV fmt chunk is too small")
                }

                audioFormat = data.uint16LittleEndian(at: chunkStart)
                channelCount = data.uint16LittleEndian(at: chunkStart + 2)
                sampleRate = data.uint32LittleEndian(at: chunkStart + 4)
                bitsPerSample = data.uint16LittleEndian(at: chunkStart + 14)
            } else if chunkID == "data" {
                dataRange = chunkStart..<chunkEnd
                break
            }

            offset = chunkStart + chunkSize + (chunkSize % 2)
        }

        guard audioFormat == 1 else {
            throw LocalWisprError.audioConversionFailed("Moonshine native only supports PCM WAV fallback audio")
        }
        guard let channels = channelCount, channels > 0 else {
            throw LocalWisprError.audioConversionFailed("WAV channel count is missing")
        }
        guard let sampleRate, sampleRate > 0 else {
            throw LocalWisprError.audioConversionFailed("WAV sample rate is missing")
        }
        guard let bitsPerSample, [16, 24, 32].contains(bitsPerSample) else {
            throw LocalWisprError.audioConversionFailed("WAV bit depth must be 16, 24, or 32-bit PCM")
        }
        guard let dataRange else {
            throw LocalWisprError.audioConversionFailed("WAV data chunk is missing")
        }

        let bytesPerSample = Int(bitsPerSample / 8)
        let bytesPerFrame = bytesPerSample * Int(channels)
        guard bytesPerFrame > 0 else {
            throw LocalWisprError.audioConversionFailed("invalid WAV frame size")
        }

        var samples: [Float] = []
        samples.reserveCapacity(dataRange.count / bytesPerFrame)
        var cursor = dataRange.lowerBound
        while cursor + bytesPerFrame <= dataRange.upperBound {
            var sum: Float = 0
            for _ in 0..<Int(channels) {
                sum += data.floatPCMSample(at: cursor, bitsPerSample: bitsPerSample)
                cursor += bytesPerSample
            }
            samples.append(sum / Float(channels))
        }

        return WAVData(samples: samples, sampleRate: Int(sampleRate))
    }
}

private extension Data {
    func asciiString(in range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        return String(data: self.subdata(in: range), encoding: .ascii)
    }

    func uint16LittleEndian(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LittleEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func floatPCMSample(at offset: Int, bitsPerSample: UInt16) -> Float {
        switch bitsPerSample {
        case 16:
            let unsigned = uint16LittleEndian(at: offset)
            let sample = Int16(bitPattern: unsigned)
            return Float(sample) / 32768.0
        case 24:
            var value = Int32(self[offset])
                | (Int32(self[offset + 1]) << 8)
                | (Int32(self[offset + 2]) << 16)
            if value & 0x800000 != 0 {
                value |= Int32(bitPattern: 0xFF000000)
            }
            return Float(value) / 8_388_608.0
        default:
            let unsigned = uint32LittleEndian(at: offset)
            let sample = Int32(bitPattern: unsigned)
            return Float(sample) / 2_147_483_648.0
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var expandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
