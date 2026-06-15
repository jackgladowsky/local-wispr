import Foundation

@MainActor
final class DictationSession {
    private enum State {
        case idle
        case preparing
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

        state = .preparing
        panelController.show(
            .init(
                phase: .listening,
                title: "Preparing mic",
                subtitle: "Local capture only",
                showsSpinner: true
            )
        )

        Task { [weak self] in
            await self?.beginRecording()
        }
    }

    func runMockDictation() {
        guard case .idle = state else { return }

        let trace = TimingTrace()
        trace.mark("record_start")
        trace.mark("record_stop")

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
            recording = try audioCapture.stop()
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

    private func beginRecording() async {
        let granted = await AudioCapture.requestMicrophoneAccessIfNeeded()
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

        guard case .preparing = state else { return }

        let trace = TimingTrace()
        trace.mark("record_start")

        do {
            try audioCapture.start()

            let context = SessionContext(
                startedAt: Date(),
                target: insertionController.captureTarget(),
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
    }

    private func process(context: SessionContext, recording: AudioRecording?, mode: ProcessingMode) async {
        do {
            let sttEngine = mode == .mock ? mockSTTEngine : sttEngine
            let rewriteEngine = mode == .mock ? mockRewriteEngine : rewriteEngine

            panelController.show(
                .init(
                    phase: .transcribing,
                    title: "Transcribing",
                    subtitle: sttEngine.name,
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

            let transcript = try await sttEngine.transcribe(request)
            try Task.checkCancellation()
            context.trace.mark("stt_final")

            panelController.show(
                .init(
                    phase: .polishing,
                    title: "Polishing",
                    subtitle: rewriteEngine.name,
                    showsSpinner: true
                )
            )

            let cleaned = try await rewriteEngine.rewrite(transcript)
            try Task.checkCancellation()
            context.trace.mark("rewrite_final")

            let insertionResult = await insertionController.insert(cleaned.text, target: context.target)
            context.trace.mark("output_final")

            let snapshot = PanelSnapshot(
                phase: insertionResult.outcome == .pasted ? .inserted : .copied,
                title: insertionResult.outcome == .pasted ? "Inserted" : "Copied",
                subtitle: insertionResult.detail,
                showsSpinner: false
            )

            panelController.show(snapshot, autoHideAfter: 1.4)
            logger.write(context.trace, insertionResult: insertionResult)
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
            logger.write(context.trace, error: error)
            state = .idle
        }
    }
}
