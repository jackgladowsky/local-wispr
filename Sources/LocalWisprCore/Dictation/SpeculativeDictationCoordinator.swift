import Foundation

struct SpeculativeDictationConfiguration: Sendable, Equatable {
    let chunkDuration: TimeInterval
    let minimumChunkDuration: TimeInterval
    let chunkArrivalGrace: TimeInterval
    let adaptiveChunking: AdaptiveAudioChunkingConfiguration?

    init(
        chunkDuration: TimeInterval = 2.5,
        minimumChunkDuration: TimeInterval = 0.25,
        chunkArrivalGrace: TimeInterval = 2.0,
        adaptiveChunking: AdaptiveAudioChunkingConfiguration? = nil
    ) {
        self.chunkDuration = max(0.5, chunkDuration)
        self.minimumChunkDuration = max(0, minimumChunkDuration)
        self.chunkArrivalGrace = max(0, chunkArrivalGrace)
        self.adaptiveChunking = adaptiveChunking
    }

    var audioChunkingConfiguration: AudioChunkingConfiguration {
        AudioChunkingConfiguration(
            chunkDuration: chunkDuration,
            minimumChunkDuration: minimumChunkDuration,
            adaptiveChunking: adaptiveChunking
        )
    }

    static var isEnabledFromEnvironment: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environmentFlag("LOCAL_WISPR_DISABLE_STREAMING", in: environment) {
            return false
        }

        return environmentFlag("LOCAL_WISPR_EXPERIMENTAL_STREAMING", in: environment, default: true)
    }

    static func fromEnvironment() -> SpeculativeDictationConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let adaptiveChunking: AdaptiveAudioChunkingConfiguration? = environmentFlag(
            "LOCAL_WISPR_STREAMING_ADAPTIVE_CHUNKS",
            in: environment,
            default: true
        ) ? AdaptiveAudioChunkingConfiguration(
            trailingSilenceDuration: environment["LOCAL_WISPR_STREAMING_SILENCE_SECONDS"].flatMap(TimeInterval.init) ?? 0.35,
            speechRMS: environment["LOCAL_WISPR_STREAMING_SPEECH_RMS"].flatMap(Float.init) ?? 0.012,
            dropsSilentChunks: environmentFlag("LOCAL_WISPR_STREAMING_DROP_SILENT_CHUNKS", in: environment)
        ) : nil

        return SpeculativeDictationConfiguration(
            chunkDuration: environment["LOCAL_WISPR_STREAMING_CHUNK_SECONDS"].flatMap(TimeInterval.init) ?? 2.5,
            minimumChunkDuration: environment["LOCAL_WISPR_STREAMING_MIN_CHUNK_SECONDS"].flatMap(TimeInterval.init) ?? 0.25,
            chunkArrivalGrace: environment["LOCAL_WISPR_STREAMING_CHUNK_GRACE_SECONDS"].flatMap(TimeInterval.init) ?? 2.0,
            adaptiveChunking: adaptiveChunking
        )
    }

    private static func environmentFlag(
        _ name: String,
        in environment: [String: String],
        default defaultValue: Bool = false
    ) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }
}

struct SpeculativeDictationDraft: Sendable, Equatable {
    let transcript: Transcript
    let speculativeCleanedText: String

    var cohesionTranscript: Transcript {
        let text = speculativeCleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? transcript.text
            : speculativeCleanedText

        return Transcript(
            text: text,
            confidence: transcript.confidence,
            segments: transcript.segments
        )
    }
}

actor SpeculativeDictationCoordinator {
    private let sttEngine: STTEngine
    private let rewriteEngine: RewriteEngine
    private let startedAt: Date
    private let configuration: SpeculativeDictationConfiguration

    private var tasks: [Int: Task<SpeculativeTranscriptChunk?, Error>] = [:]
    private var skippedChunkIndices = Set<Int>()
    private var isClosed = false

    init(
        sttEngine: STTEngine,
        rewriteEngine: RewriteEngine,
        startedAt: Date,
        configuration: SpeculativeDictationConfiguration = .fromEnvironment()
    ) {
        self.sttEngine = sttEngine
        self.rewriteEngine = rewriteEngine
        self.startedAt = startedAt
        self.configuration = configuration
    }

    func accept(_ chunk: AudioChunk) {
        guard !isClosed else {
            chunk.removeTemporaryFiles()
            return
        }

        enqueue(chunk)
    }

    func finish(finalChunks: [AudioChunk], expectedChunkCount: Int?) async throws -> SpeculativeDictationDraft {
        for chunk in finalChunks {
            enqueue(chunk)
        }

        try await waitForExpectedChunks(expectedChunkCount)

        let orderedTasks = tasks.sorted { $0.key < $1.key }
        guard !orderedTasks.isEmpty else {
            throw LocalWisprError.emptyTranscript
        }

        var accumulator = SpeculativeChunkAccumulator()
        for (_, task) in orderedTasks {
            if let chunk = try await task.value {
                accumulator.record(chunk)
            }
        }

        isClosed = true

        guard let transcript = accumulator.rawTranscript() else {
            throw LocalWisprError.emptyTranscript
        }

        let speculativeCleanedText = accumulator.speculativeCleanedDraft()
        return SpeculativeDictationDraft(
            transcript: transcript,
            speculativeCleanedText: speculativeCleanedText
        )
    }

    func cancel() {
        isClosed = true
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        skippedChunkIndices.removeAll()
    }

    private func enqueue(_ chunk: AudioChunk) {
        guard !isClosed else {
            chunk.removeTemporaryFiles()
            return
        }
        guard tasks[chunk.index] == nil, !skippedChunkIndices.contains(chunk.index) else {
            chunk.removeTemporaryFiles()
            return
        }

        guard chunk.shouldTranscribe else {
            skippedChunkIndices.insert(chunk.index)
            chunk.removeTemporaryFiles()
            return
        }

        guard chunk.duration >= configuration.minimumChunkDuration else {
            skippedChunkIndices.insert(chunk.index)
            chunk.removeTemporaryFiles()
            return
        }

        let sttEngine = sttEngine
        let rewriteEngine = rewriteEngine
        let sessionStartedAt = startedAt

        tasks[chunk.index] = Task(priority: .userInitiated) {
            try await Self.process(
                chunk: chunk,
                sttEngine: sttEngine,
                rewriteEngine: rewriteEngine,
                sessionStartedAt: sessionStartedAt
            )
        }
    }

    private func waitForExpectedChunks(_ expectedChunkCount: Int?) async throws {
        guard let expectedChunkCount, expectedChunkCount > 0 else { return }

        let deadline = Date().addingTimeInterval(configuration.chunkArrivalGrace)
        while !hasAcceptedAllChunks(upTo: expectedChunkCount) {
            if Date() >= deadline {
                throw LocalWisprError.cleanupFailed(
                    "Streaming STT missed an audio chunk before release; falling back to batch"
                )
            }

            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func hasAcceptedAllChunks(upTo expectedChunkCount: Int) -> Bool {
        for index in 0..<expectedChunkCount where tasks[index] == nil && !skippedChunkIndices.contains(index) {
            return false
        }
        return true
    }

    private static func process(
        chunk: AudioChunk,
        sttEngine: STTEngine,
        rewriteEngine: RewriteEngine,
        sessionStartedAt: Date
    ) async throws -> SpeculativeTranscriptChunk? {
        defer { chunk.removeTemporaryFiles() }

        let request = TranscriptionRequest(
            startedAt: chunk.startedAt,
            endedAt: chunk.endedAt,
            source: .microphone,
            audioURL: chunk.wavURL,
            duration: chunk.duration
        )

        let transcript: Transcript
        do {
            transcript = try await sttEngine.transcribe(request)
        } catch LocalWisprError.emptyTranscript {
            return nil
        }

        try Task.checkCancellation()

        let cleaned = try await rewriteEngine.rewrite(transcript)
        try Task.checkCancellation()

        return SpeculativeTranscriptChunk(
            index: chunk.index,
            rawText: transcript.text,
            cleanedText: cleaned.text,
            startTime: max(0, chunk.startedAt.timeIntervalSince(sessionStartedAt)),
            endTime: max(0, chunk.endedAt.timeIntervalSince(sessionStartedAt))
        )
    }
}
