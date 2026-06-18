@testable import LocalWisprCore
import Foundation
import Testing

@Test
func streamingAudioBufferDurationUsesSampleRate() {
    let buffer = StreamingAudioBuffer(
        samples: Array(repeating: 0.1, count: 800),
        sampleRate: 16000,
        receivedAt: Date()
    )

    #expect(buffer.duration == 0.05)
}

@Test
func streamingAudioFeederAggregatesAndFlushesBuffers() async throws {
    let session = RecordingStreamingSession()
    let feeder = StreamingSTTAudioFeeder(
        session: session,
        targetBufferDuration: 0.1,
        trailingSilenceDuration: 0
    )
    let now = Date()

    await feeder.accept(
        StreamingAudioBuffer(
            samples: Array(repeating: 0.1, count: 800),
            sampleRate: 16000,
            receivedAt: now
        )
    )
    #expect(session.appendedBuffers.isEmpty)

    await feeder.accept(
        StreamingAudioBuffer(
            samples: Array(repeating: 0.2, count: 800),
            sampleRate: 16000,
            receivedAt: now.addingTimeInterval(0.05)
        )
    )

    try await feeder.finish()

    let appended = session.appendedBuffers
    #expect(appended.count == 1)
    #expect(appended.first?.samples.count == 1600)
    #expect(appended.first?.sampleRate == 16000)
}

@Test
func streamingAudioFeederAppendsTrailingSilenceOnFinish() async throws {
    let session = RecordingStreamingSession()
    let feeder = StreamingSTTAudioFeeder(
        session: session,
        targetBufferDuration: 0.1,
        trailingSilenceDuration: 0.05
    )
    let now = Date()

    await feeder.accept(
        StreamingAudioBuffer(
            samples: Array(repeating: 0.1, count: 1600),
            sampleRate: 16000,
            receivedAt: now
        )
    )

    try await feeder.finish()

    let appended = session.appendedBuffers
    #expect(appended.count == 2)
    #expect(appended[0].samples.count == 1600)
    #expect(appended[1].samples.count == 800)
    #expect(appended[1].samples.allSatisfy { $0 == 0 })
}

@Test
func fallbackSTTEngineStartsStreamingSessionFromPrimary() async throws {
    let primary = RecordingStreamingEngine()
    let fallback = NonStreamingSTTEngine()
    let engine = FallbackSTTEngine(primary: primary, fallback: fallback)

    let session = try await engine.startStreamingSession(startedAt: Date())

    #expect(session.name == "Recording streaming")
}

private final class RecordingStreamingSession: StreamingSTTSession, @unchecked Sendable {
    let name = "Recording streaming"

    private let lock = NSLock()
    private var storage: [StreamingAudioBuffer] = []

    var appendedBuffers: [StreamingAudioBuffer] {
        lock.withLock { storage }
    }

    func append(_ buffer: StreamingAudioBuffer) async throws {
        lock.withLock {
            storage.append(buffer)
        }
    }

    func finish(endedAt: Date) async throws -> Transcript {
        Transcript(text: "done", confidence: nil, segments: [])
    }

    func cancel() async {}
}

private struct RecordingStreamingEngine: StreamingSTTEngine {
    let name = "Recording"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        Transcript(text: "batch", confidence: nil, segments: [])
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        RecordingStreamingSession()
    }
}

private struct NonStreamingSTTEngine: STTEngine {
    let name = "Batch only"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        Transcript(text: "fallback", confidence: nil, segments: [])
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
