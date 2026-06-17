import Foundation

@MainActor
final class DictationSession {
    private enum State {
        case idle
        case preparing(TimingTrace)
        case recording(SessionContext)
        case processing
    }

    private struct SessionContext {
        let startedAt: Date
        let target: InsertionTarget?
        let trace: TimingTrace
        let speculativeCoordinator: SpeculativeDictationCoordinator?

        init(
            startedAt: Date,
            target: InsertionTarget?,
            trace: TimingTrace,
            speculativeCoordinator: SpeculativeDictationCoordinator? = nil
        ) {
            self.startedAt = startedAt
            self.target = target
            self.trace = trace
            self.speculativeCoordinator = speculativeCoordinator
        }
    }

    private let panelController: DictationPanelController
    private let audioCapture: AudioCapture
    private let sttEngine: STTEngine
    private let rewriteEngine: RewriteEngine
    private let mockSTTEngine: STTEngine
    private let mockRewriteEngine: RewriteEngine
    private let insertionController: InsertionController
    private let logger: TimingLogger

    private var state: State = .idle
    private var processingTask: Task<Void, Never>?

    init(
        panelController: DictationPanelController,
        audioCapture: AudioCapture,
        sttEngine: STTEngine,
        rewriteEngine: RewriteEngine,
        insertionController: InsertionController,
        logger: TimingLogger
    ) {
        self.panelController = panelController
        self.audioCapture = audioCapture
        self.sttEngine = sttEngine
        self.rewriteEngine = rewriteEngine
        self.mockSTTEngine = MockSTTEngine()
        self.mockRewriteEngine = MockRewriteEngine()
        self.insertionController = insertionController
        self.logger = logger
    }

    func startRecording() {
        guard case .idle = state else { return }

        let trace = TimingTrace()
        trace.mark("hotkey_down")

        state = .preparing(trace)
        panelController.show(
            .init(
                phase: .listening,
                title: "Preparing mic",
                subtitle: "Local capture only",
                showsSpinner: true
            )
        )

        Task { [weak self] in
            await self?.beginRecording(trace: trace)
        }
    }

    func runMockDictation() {
        guard case .idle = state else { return }

        let trace = TimingTrace()
        trace.mark("hotkey_down")
        trace.mark("record_start")
        trace.mark("record_stop")
        trace.mark("audio_stop_begin")
        trace.mark("audio_stop_end")

        let context = SessionContext(
            startedAt: Date(),
            target: insertionController.captureTarget(),
            trace: trace
        )

        state = .processing
        panelController.show(
            .init(
                phase: .transcribing,
                title: "Simulating",
                subtitle: "Mock local engines",
                showsSpinner: true
            )
        )

        processingTask = Task { [weak self] in
            await self?.process(context: context, recording: nil, mode: .mock)
        }
    }

    func stopRecording() {
        guard case .recording(let context) = state else { return }

        context.trace.mark("record_stop")
        state = .processing

        let recording: AudioRecording
        let fullSessionWavConversion: FullSessionWavConversion = context.speculativeCoordinator != nil && Self.shouldDeferStreamingFallbackAudio
            ? .deferred
            : .synchronous
        do {
            context.trace.mark("audio_stop_begin")
            recording = try audioCapture.stop(fullSessionWavConversion: fullSessionWavConversion)
            context.trace.mark("audio_stop_end")
        } catch {
            state = .idle
            panelController.show(
                .init(
                    phase: .error,
                    title: "Recording failed",
                    subtitle: error.localizedDescription,
                    showsSpinner: false
                ),
                autoHideAfter: 3.0
            )
            logger.write(context.trace, error: error)
            return
        }

        processingTask = Task { [weak self] in
            await self?.process(context: context, recording: recording, mode: .real)
        }
    }

    func cancel() {
        let speculativeCoordinator: SpeculativeDictationCoordinator?
        if case .recording(let context) = state {
            speculativeCoordinator = context.speculativeCoordinator
        } else {
            speculativeCoordinator = nil
        }

        processingTask?.cancel()
        processingTask = nil
        audioCapture.cancel()
        Task {
            await speculativeCoordinator?.cancel()
        }
        state = .idle

        panelController.show(
            .init(
                phase: .canceled,
                title: "Canceled",
                subtitle: "Nothing inserted",
                showsSpinner: false
            ),
            autoHideAfter: 1.2
        )
    }

    private func beginRecording(trace: TimingTrace) async {
        trace.mark("mic_permission_start")
        let granted = await AudioCapture.requestMicrophoneAccessIfNeeded()
        trace.mark("mic_permission_end")

        guard granted else {
            state = .idle
            panelController.show(
                .init(
                    phase: .error,
                    title: "Microphone blocked",
                    subtitle: "Grant microphone permission",
                    showsSpinner: false
                ),
                autoHideAfter: 4.0
            )
            return
        }

        guard case .preparing(let currentTrace) = state, currentTrace.id == trace.id else { return }

        do {
            let recordingStartedAt = Date()
            let speculativeConfiguration = SpeculativeDictationConfiguration.isEnabledFromEnvironment
                ? SpeculativeDictationConfiguration.fromEnvironment()
                : nil
            let speculativeCoordinator = speculativeConfiguration.map {
                SpeculativeDictationCoordinator(
                    sttEngine: sttEngine,
                    rewriteEngine: rewriteEngine,
                    startedAt: recordingStartedAt,
                    configuration: $0
                )
            }

            trace.mark("audio_start_begin")
            let onChunkFinalized: (@Sendable (AudioChunk) -> Void)?
            if let speculativeCoordinator {
                onChunkFinalized = { chunk in
                    Task {
                        await speculativeCoordinator.accept(chunk)
                    }
                }
            } else {
                onChunkFinalized = nil
            }
            try audioCapture.start(
                chunking: speculativeConfiguration?.audioChunkingConfiguration,
                onChunkFinalized: onChunkFinalized
            )
            trace.mark("audio_start_end")
            trace.mark("record_start")

            trace.mark("target_capture_start")
            let target = insertionController.captureTarget()
            trace.mark("target_capture_end")

            let context = SessionContext(
                startedAt: recordingStartedAt,
                target: target,
                trace: trace,
                speculativeCoordinator: speculativeCoordinator
            )

            state = .recording(context)
            panelController.show(
                .init(
                    phase: .listening,
                    title: "Listening",
                    subtitle: speculativeCoordinator == nil ? "Release to insert" : "Streaming locally",
                    showsSpinner: false
                )
            )
        } catch {
            state = .idle
            panelController.show(
                .init(
                    phase: .error,
                    title: "Mic start failed",
                    subtitle: error.localizedDescription,
                    showsSpinner: false
                ),
                autoHideAfter: 4.0
            )
            logger.write(trace, error: error)
        }
    }

    private enum ProcessingMode {
        case real
        case mock

        var logValue: String {
            switch self {
            case .real:
                "real"
            case .mock:
                "mock"
            }
        }
    }

    private func process(context: SessionContext, recording: AudioRecording?, mode: ProcessingMode) async {
        defer { recording?.removeTemporaryFiles() }

        let activeSTTEngine: STTEngine = mode == .mock ? mockSTTEngine : sttEngine
        let activeRewriteEngine: RewriteEngine = mode == .mock ? mockRewriteEngine : rewriteEngine

        do {
            if
                mode == .real,
                let recording,
                let speculativeCoordinator = context.speculativeCoordinator
            {
                do {
                    let (transcript, cleaned) = try await runSpeculativePipeline(
                        context: context,
                        recording: recording,
                        coordinator: speculativeCoordinator,
                        sttEngine: activeSTTEngine,
                        rewriteEngine: activeRewriteEngine
                    )
                    try Task.checkCancellation()
                    await insertAndLog(
                        context: context,
                        recording: recording,
                        modeLogValue: "real-streaming",
                        sttEngineName: activeSTTEngine.name,
                        rewriteEngineName: activeRewriteEngine.name,
                        transcript: transcript,
                        cleaned: cleaned
                    )
                    return
                } catch is CancellationError {
                    await speculativeCoordinator.cancel()
                    throw CancellationError()
                } catch {
                    await speculativeCoordinator.cancel()
                    context.trace.mark("streaming_fallback")
                    NSLog("LocalWispr streaming STT failed; falling back to batch: \(error.localizedDescription)")
                }
            }

            panelController.show(
                .init(
                    phase: .transcribing,
                    title: "Transcribing",
                    subtitle: activeSTTEngine.name,
                    showsSpinner: true
                )
            )

            let audioURL = try await recording?.whisperReadyWavURL()
            let request = TranscriptionRequest(
                startedAt: context.startedAt,
                endedAt: recording?.endedAt ?? Date(),
                source: mode == .mock ? .mock : .microphone,
                audioURL: audioURL,
                duration: recording?.duration ?? max(0.1, Date().timeIntervalSince(context.startedAt))
            )

            context.trace.mark("stt_start")
            let transcript = try await activeSTTEngine.transcribe(request)
            try Task.checkCancellation()
            context.trace.mark("stt_final")

            panelController.show(
                .init(
                    phase: .polishing,
                    title: "Polishing",
                    subtitle: activeRewriteEngine.name,
                    showsSpinner: true
                )
            )

            context.trace.mark("rewrite_start")
            let cleaned = try await activeRewriteEngine.rewrite(transcript)
            try Task.checkCancellation()
            context.trace.mark("rewrite_final")

            await insertAndLog(
                context: context,
                recording: recording,
                modeLogValue: mode.logValue,
                sttEngineName: activeSTTEngine.name,
                rewriteEngineName: activeRewriteEngine.name,
                transcript: transcript,
                cleaned: cleaned
            )
        } catch is CancellationError {
            state = .idle
        } catch {
            context.trace.mark("error")
            panelController.show(
                .init(
                    phase: .error,
                    title: "Dictation failed",
                    subtitle: error.localizedDescription,
                    showsSpinner: false
                ),
                autoHideAfter: 3.0
            )
            logger.write(
                context.trace,
                error: error,
                mode: mode.logValue,
                sttEngineName: activeSTTEngine.name,
                rewriteEngineName: activeRewriteEngine.name
            )
            state = .idle
        }
    }

    private func runSpeculativePipeline(
        context: SessionContext,
        recording: AudioRecording,
        coordinator: SpeculativeDictationCoordinator,
        sttEngine: STTEngine,
        rewriteEngine: RewriteEngine
    ) async throws -> (Transcript, CleanedText) {
        panelController.show(
            .init(
                phase: .transcribing,
                title: "Finalizing tail",
                subtitle: "Streaming STT",
                showsSpinner: true
            )
        )

        guard let expectedStreamingChunkCount = recording.expectedStreamingChunkCount else {
            throw LocalWisprError.cleanupFailed(
                "Streaming STT did not receive a complete chunking summary; falling back to batch"
            )
        }

        context.trace.mark("stt_start")
        let draft = try await coordinator.finish(
            finalChunks: recording.chunks,
            expectedChunkCount: expectedStreamingChunkCount
        )
        try Task.checkCancellation()
        context.trace.mark("stt_final")

        if Self.shouldSkipFinalSpeculativeCleanup {
            context.trace.mark("rewrite_start")
            let text = draft.cohesionTranscript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw LocalWisprError.emptyTranscript
            }
            context.trace.mark("rewrite_final")

            return (
                draft.transcript,
                CleanedText(text: text, engineName: "Speculative chunks, no final cleanup")
            )
        }

        panelController.show(
            .init(
                phase: .polishing,
                title: "Cohesion pass",
                subtitle: rewriteEngine.name,
                showsSpinner: true
            )
        )

        context.trace.mark("rewrite_start")
        let cohesion = try await rewriteEngine.rewrite(draft.cohesionTranscript)
        try Task.checkCancellation()
        context.trace.mark("rewrite_final")

        let engineName = cohesion.engineName.map { "Speculative chunks + \($0)" }
            ?? "Speculative chunks + \(rewriteEngine.name)"
        return (
            draft.transcript,
            CleanedText(text: cohesion.text, engineName: engineName)
        )
    }

    private static var shouldSkipFinalSpeculativeCleanup: Bool {
        isEnabledEnvironmentFlag("LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP", default: true)
    }

    private static var shouldDeferStreamingFallbackAudio: Bool {
        isEnabledEnvironmentFlag("LOCAL_WISPR_STREAMING_DEFER_FULL_WAV", default: true)
    }

    private static func isEnabledEnvironmentFlag(_ name: String, default defaultValue: Bool = false) -> Bool {
        switch ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }

    private func insertAndLog(
        context: SessionContext,
        recording: AudioRecording?,
        modeLogValue: String,
        sttEngineName: String,
        rewriteEngineName: String,
        transcript: Transcript,
        cleaned: CleanedText
    ) async {
        context.trace.mark("insert_start")
        let insertionResult = await insertionController.insert(cleaned.text, target: context.target)
        context.trace.mark("output_final")

        let snapshot = PanelSnapshot(
            phase: insertionResult.outcome == .pasted ? .inserted : .copied,
            title: insertionResult.outcome == .pasted ? "Inserted" : "Copied",
            subtitle: insertionResult.detail,
            showsSpinner: false
        )

        panelController.show(snapshot, autoHideAfter: 1.4)
        logger.write(
            context.trace,
            insertionResult: insertionResult,
            mode: modeLogValue,
            recording: recording,
            sttEngineName: sttEngineName,
            rewriteEngineName: rewriteEngineName,
            transcript: transcript,
            cleaned: cleaned
        )
        state = .idle
    }
}
