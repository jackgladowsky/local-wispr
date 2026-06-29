import Foundation

actor StreamingSTTAudioFeeder {
    private let session: StreamingSTTSession
    private let targetBufferDuration: TimeInterval
    private let trailingSilenceDuration: TimeInterval

    private var pendingSamples: [Float] = []
    private var pendingSampleRate: Double?
    private var pendingReceivedAt: Date?
    private var lastSampleRate: Double?
    private var trailingSilentFrames: Int = 0
    private var appendTask: Task<Error?, Never>?
    private var appendError: Error?
    private var isClosed = false

    init(
        session: StreamingSTTSession,
        targetBufferDuration: TimeInterval? = nil,
        trailingSilenceDuration: TimeInterval? = nil
    ) {
        self.session = session
        self.targetBufferDuration = max(0.02, targetBufferDuration ?? StreamingSTTAudioFeeder.defaultTargetBufferDuration())
        self.trailingSilenceDuration = max(0, trailingSilenceDuration ?? StreamingSTTAudioFeeder.defaultTrailingSilenceDuration())
    }

    func accept(_ buffer: StreamingAudioBuffer) async {
        guard !isClosed, appendError == nil, !buffer.samples.isEmpty else { return }

        lastSampleRate = buffer.sampleRate
        updateTrailingSilence(with: buffer.samples)

        if
            let pendingSampleRate,
            abs(pendingSampleRate - buffer.sampleRate) > 0.001
        {
            flushAllPendingSamples()
        }

        if pendingSamples.isEmpty {
            pendingSampleRate = buffer.sampleRate
            pendingReceivedAt = buffer.receivedAt
        }

        let targetFrames = targetFrameCount(for: buffer.sampleRate)
        pendingSamples.reserveCapacity(max(pendingSamples.capacity, targetFrames + buffer.samples.count))
        pendingSamples.append(contentsOf: buffer.samples)
        flushTargetSizedSamplesIfNeeded()
    }

    func finish() async throws {
        isClosed = true
        appendTrailingSilenceIfNeeded()
        flushAllPendingSamples()

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
        lastSampleRate = nil
        trailingSilentFrames = 0
        appendTask?.cancel()
        await session.cancel()
    }

    private func appendTrailingSilenceIfNeeded() {
        guard trailingSilenceDuration > 0 else { return }
        guard let sampleRate = pendingSampleRate ?? lastSampleRate, sampleRate.isFinite, sampleRate > 0 else { return }

        let silenceFrameCount = Int((trailingSilenceDuration * sampleRate).rounded(.up))
        guard silenceFrameCount > 0, trailingSilentFrames < silenceFrameCount else { return }

        if pendingSamples.isEmpty {
            pendingSampleRate = sampleRate
            pendingReceivedAt = Date()
        }

        let framesToAppend = silenceFrameCount - trailingSilentFrames
        pendingSamples.reserveCapacity(pendingSamples.count + framesToAppend)
        pendingSamples.append(contentsOf: Array(repeating: 0, count: framesToAppend))
        trailingSilentFrames += framesToAppend
    }

    private func flushTargetSizedSamplesIfNeeded() {
        guard appendError == nil, let sampleRate = pendingSampleRate else { return }
        let targetFrames = targetFrameCount(for: sampleRate)

        while pendingSamples.count >= targetFrames {
            flushPendingPrefix(frameCount: targetFrames)
        }
    }

    private func flushAllPendingSamples() {
        guard appendError == nil, !pendingSamples.isEmpty else { return }
        flushPendingPrefix(frameCount: pendingSamples.count)
    }

    private func flushPendingPrefix(frameCount: Int) {
        guard appendError == nil, !pendingSamples.isEmpty else { return }
        guard let sampleRate = pendingSampleRate else { return }

        let count = min(max(1, frameCount), pendingSamples.count)
        let samples = Array(pendingSamples.prefix(count))
        let buffer = StreamingAudioBuffer(
            samples: samples,
            sampleRate: sampleRate,
            receivedAt: pendingReceivedAt ?? Date()
        )

        pendingSamples.removeFirst(count)
        if pendingSamples.isEmpty {
            pendingSampleRate = nil
            pendingReceivedAt = nil
        }

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

    private func targetFrameCount(for sampleRate: Double) -> Int {
        guard sampleRate.isFinite, sampleRate > 0 else { return 1 }
        return max(1, Int((targetBufferDuration * sampleRate).rounded(.up)))
    }

    private func updateTrailingSilence(with samples: [Float]) {
        let silenceThreshold: Float = 0.000_5
        var silentSuffixCount = 0
        for sample in samples.reversed() {
            if abs(sample) <= silenceThreshold {
                silentSuffixCount += 1
            } else {
                break
            }
        }

        trailingSilentFrames = silentSuffixCount == samples.count
            ? trailingSilentFrames + silentSuffixCount
            : silentSuffixCount
    }

    private static func defaultTargetBufferDuration() -> TimeInterval {
        ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_STREAM_UPLOAD_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.02, $0) }
            ?? 0.10
    }

    private static func defaultTrailingSilenceDuration() -> TimeInterval {
        ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_TRAILING_SILENCE_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0, $0) }
            ?? 0.15
    }
}
