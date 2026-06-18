import Foundation

actor StreamingSTTAudioFeeder {
    private let session: StreamingSTTSession
    private let targetBufferDuration: TimeInterval

    private var pendingSamples: [Float] = []
    private var pendingSampleRate: Double?
    private var pendingReceivedAt: Date?
    private var appendTask: Task<Error?, Never>?
    private var appendError: Error?
    private var isClosed = false

    init(
        session: StreamingSTTSession,
        targetBufferDuration: TimeInterval? = nil
    ) {
        self.session = session
        self.targetBufferDuration = max(0.02, targetBufferDuration ?? StreamingSTTAudioFeeder.defaultTargetBufferDuration())
    }

    func accept(_ buffer: StreamingAudioBuffer) async {
        guard !isClosed, appendError == nil, !buffer.samples.isEmpty else { return }

        if
            let pendingSampleRate,
            abs(pendingSampleRate - buffer.sampleRate) > 0.001
        {
            flushPendingSamples()
        }

        if pendingSamples.isEmpty {
            pendingSampleRate = buffer.sampleRate
            pendingReceivedAt = buffer.receivedAt
        }

        pendingSamples.append(contentsOf: buffer.samples)

        guard let pendingSampleRate, pendingSampleRate > 0 else { return }
        let targetFrames = max(1, Int((targetBufferDuration * pendingSampleRate).rounded(.up)))
        if pendingSamples.count >= targetFrames {
            flushPendingSamples()
        }
    }

    func finish() async throws {
        isClosed = true
        flushPendingSamples()

        if let taskError = await appendTask?.value {
            appendError = taskError
        }

        if let appendError {
            throw appendError
        }
    }

    func cancel() async {
        isClosed = true
        pendingSamples.removeAll()
        pendingSampleRate = nil
        pendingReceivedAt = nil
        appendTask?.cancel()
        await session.cancel()
    }

    private func flushPendingSamples() {
        guard appendError == nil, !pendingSamples.isEmpty else { return }
        guard let sampleRate = pendingSampleRate else { return }

        let buffer = StreamingAudioBuffer(
            samples: pendingSamples,
            sampleRate: sampleRate,
            receivedAt: pendingReceivedAt ?? Date()
        )
        pendingSamples.removeAll(keepingCapacity: true)
        pendingSampleRate = nil
        pendingReceivedAt = nil

        let previousTask = appendTask
        let session = session
        appendTask = Task {
            if let previousError = await previousTask?.value {
                return previousError
            }

            do {
                try await session.append(buffer)
                return nil
            } catch {
                return error
            }
        }
    }

    private static func defaultTargetBufferDuration() -> TimeInterval {
        ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_STREAM_UPLOAD_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.02, $0) }
            ?? 0.10
    }
}
