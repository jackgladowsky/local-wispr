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
        do {
            context.trace.mark("audio_stop_begin")
            recording = try audioCapture.stop()
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
        processingTask?.cancel()
        processingTask = nil
        audioCapture.cancel()
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
            trace.mark("audio_start_begin")
            try audioCapture.start()
            trace.mark("audio_start_end")
            trace.mark("record_start")

            trace.mark("target_capture_start")
            let target = insertionController.captureTarget()
            trace.mark("target_capture_end")

            let context = SessionContext(
                startedAt: Date(),
                target: target,
                trace: trace
            )

            state = .recording(context)
            panelController.show(
                .init(
                    phase: .listening,
                    title: "Listening",
                    subtitle: "Release to insert",
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
        let activeSTTEngine: STTEngine = mode == .mock ? mockSTTEngine : sttEngine
        let activeRewriteEngine: RewriteEngine = mode == .mock ? mockRewriteEngine : rewriteEngine

        do {
            panelController.show(
                .init(
                    phase: .transcribing,
                    title: "Transcribing",
                    subtitle: activeSTTEngine.name,
                    showsSpinner: true
                )
            )

            let request = TranscriptionRequest(
                startedAt: context.startedAt,
                endedAt: recording?.endedAt ?? Date(),
                source: mode == .mock ? .mock : .microphone,
                audioURL: recording?.wavURL,
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
                mode: mode.logValue,
                recording: recording,
                sttEngineName: activeSTTEngine.name,
                rewriteEngineName: activeRewriteEngine.name,
                transcript: transcript,
                cleaned: cleaned
            )
            state = .idle
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
}
