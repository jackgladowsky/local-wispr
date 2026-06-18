@testable import LocalWisprCore
import Foundation
import Testing

@Test
func moonshineNativeDiscoveryUsesExplicitValidModelDirectory() throws {
    let directory = try temporaryModelDirectory(arch: .smallStreaming)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let engine = MoonshineNativeEngine.discover(environment: [
        "LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR": directory.path,
        "LOCAL_WISPR_MOONSHINE_LANGUAGE": "en",
        "LOCAL_WISPR_MOONSHINE_VOICE_ARCH": "small-streaming"
    ])

    #expect(engine?.modelDirectory.path == directory.path)
    #expect(engine?.language == "en")
    #expect(engine?.arch == .smallStreaming)
}

@Test
func moonshineNativeDiscoveryCanBeDisabled() throws {
    let directory = try temporaryModelDirectory(arch: .smallStreaming)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let engine = MoonshineNativeEngine.discover(environment: [
        "LOCAL_WISPR_DISABLE_MOONSHINE_NATIVE": "1",
        "LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR": directory.path
    ])

    #expect(engine == nil)
}

@Test
func moonshineNativeDiscoveryHonorsServerOnlyEngine() throws {
    let directory = try temporaryModelDirectory(arch: .smallStreaming)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let engine = MoonshineNativeEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "moonshine-server",
        "LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR": directory.path
    ])

    #expect(engine == nil)
}

@Test
func moonshineNativeStreamingSessionReturnsCleanTranscript() async throws {
    let stream = FakeNativeStream(
        finishTranscript: MoonshineNativeTranscript(lines: [
            .init(text: " hello   native moonshine ", startTime: 0.1, duration: 0.7)
        ])
    )
    let engine = MoonshineNativeEngine(
        modelDirectory: URL(fileURLWithPath: "/tmp/fake-moonshine-model"),
        runtime: FakeNativeRuntime(transcriber: FakeNativeTranscriber(stream: stream))
    )

    let session = try await engine.startStreamingSession(startedAt: Date(timeIntervalSince1970: 10))
    try await session.append(
        StreamingAudioBuffer(
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000,
            receivedAt: Date(timeIntervalSince1970: 10.1)
        )
    )
    let transcript = try await session.finish(endedAt: Date(timeIntervalSince1970: 11))

    #expect(transcript.text == "hello native moonshine")
    #expect(transcript.segments.count == 1)
    #expect(transcript.segments.first?.text == "hello native moonshine")
    #expect(abs((transcript.segments.first?.startTime ?? 0) - 0.1) < 0.001)
    #expect(abs((transcript.segments.first?.endTime ?? 0) - 0.8) < 0.001)
    #expect(stream.appendedSampleCounts == [3])
}

@Test
func moonshineNativeStreamingSessionPropagatesAppendErrors() async throws {
    let expected = FakeNativeError()
    let stream = FakeNativeStream(
        appendError: expected,
        finishTranscript: MoonshineNativeTranscript(lines: [])
    )
    let engine = MoonshineNativeEngine(
        modelDirectory: URL(fileURLWithPath: "/tmp/fake-moonshine-model"),
        runtime: FakeNativeRuntime(transcriber: FakeNativeTranscriber(stream: stream))
    )
    let session = try await engine.startStreamingSession(startedAt: Date())

    do {
        try await session.append(
            StreamingAudioBuffer(samples: [0.1], sampleRate: 16_000, receivedAt: Date())
        )
        Issue.record("Expected native append failure")
    } catch {
        #expect(error is FakeNativeError)
    }
}

@Test
func moonshineNativeEngineReusesLoadedTranscriberAcrossSessions() async throws {
    let runtime = CountingNativeRuntime()
    let engine = MoonshineNativeEngine(
        modelDirectory: URL(fileURLWithPath: "/tmp/fake-moonshine-model"),
        runtime: runtime
    )

    _ = try await engine.startStreamingSession(startedAt: Date())
    _ = try await engine.startStreamingSession(startedAt: Date())

    #expect(runtime.makeTranscriberCount == 1)
}

@Test
func moonshineNativeBatchTranscriptionLoadsWavThroughRuntime() async throws {
    let wavURL = try temporaryWavURL(samples: [0, 16_384, -16_384, 32_767], sampleRate: 16_000)
    defer { try? FileManager.default.removeItem(at: wavURL.deletingLastPathComponent()) }

    let transcriber = FakeNativeTranscriber(
        batchTranscript: MoonshineNativeTranscript(lines: [
            .init(text: "batch transcript", startTime: 0, duration: 0.25)
        ]),
        stream: FakeNativeStream(finishTranscript: MoonshineNativeTranscript(lines: []))
    )
    let engine = MoonshineNativeEngine(
        modelDirectory: URL(fileURLWithPath: "/tmp/fake-moonshine-model"),
        runtime: FakeNativeRuntime(transcriber: transcriber)
    )

    let transcript = try await engine.transcribe(
        TranscriptionRequest(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            source: .fixture,
            audioURL: wavURL,
            duration: 1
        )
    )

    #expect(transcript.text == "batch transcript")
    #expect(transcriber.lastBatchSampleRate == 16_000)
    #expect(transcriber.lastBatchSampleCount == 4)
}

private func temporaryModelDirectory(arch: MoonshineNativeModelArch) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("model", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for fileName in arch.requiredModelFiles {
        try Data("test".utf8).write(to: directory.appendingPathComponent(fileName))
    }
    return directory
}

private func temporaryWavURL(samples: [Int16], sampleRate: UInt32) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("audio.wav")

    var data = Data()
    data.appendASCII("RIFF")
    data.appendUInt32LE(UInt32(36 + samples.count * 2))
    data.appendASCII("WAVE")
    data.appendASCII("fmt ")
    data.appendUInt32LE(16)
    data.appendUInt16LE(1)
    data.appendUInt16LE(1)
    data.appendUInt32LE(sampleRate)
    data.appendUInt32LE(sampleRate * 2)
    data.appendUInt16LE(2)
    data.appendUInt16LE(16)
    data.appendASCII("data")
    data.appendUInt32LE(UInt32(samples.count * 2))
    for sample in samples {
        data.appendUInt16LE(UInt16(bitPattern: sample))
    }

    try data.write(to: url)
    return url
}

private struct FakeNativeRuntime: MoonshineNativeRuntime {
    let transcriber: FakeNativeTranscriber

    func makeTranscriber(modelDirectory: URL, arch: MoonshineNativeModelArch) async throws -> any MoonshineNativeTranscribing {
        transcriber
    }
}

private final class FakeNativeTranscriber: MoonshineNativeTranscribing, @unchecked Sendable {
    let batchTranscript: MoonshineNativeTranscript
    let stream: FakeNativeStream

    private let lock = NSLock()
    private var batchSampleRate: Int32?
    private var batchSampleCount: Int?

    init(
        batchTranscript: MoonshineNativeTranscript = MoonshineNativeTranscript(lines: []),
        stream: FakeNativeStream
    ) {
        self.batchTranscript = batchTranscript
        self.stream = stream
    }

    var lastBatchSampleRate: Int32? {
        lock.withLock { batchSampleRate }
    }

    var lastBatchSampleCount: Int? {
        lock.withLock { batchSampleCount }
    }

    func transcribe(samples: [Float], sampleRate: Int32) async throws -> MoonshineNativeTranscript {
        lock.withLock {
            batchSampleRate = sampleRate
            batchSampleCount = samples.count
        }
        return batchTranscript
    }

    func startStream(updateInterval: TimeInterval) async throws -> any MoonshineNativeStreaming {
        stream
    }
}

private final class FakeNativeStream: MoonshineNativeStreaming, @unchecked Sendable {
    let appendError: Error?
    let finishTranscript: MoonshineNativeTranscript

    private let lock = NSLock()
    private var sampleCounts: [Int] = []

    init(
        appendError: Error? = nil,
        finishTranscript: MoonshineNativeTranscript
    ) {
        self.appendError = appendError
        self.finishTranscript = finishTranscript
    }

    var appendedSampleCounts: [Int] {
        lock.withLock { sampleCounts }
    }

    func append(samples: [Float], sampleRate: Int32) async throws {
        if let appendError {
            throw appendError
        }

        lock.withLock {
            sampleCounts.append(samples.count)
        }
    }

    func finish() async throws -> MoonshineNativeTranscript {
        finishTranscript
    }

    func cancel() async {}
}

private final class CountingNativeRuntime: MoonshineNativeRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var makeTranscriberCount: Int {
        lock.withLock { count }
    }

    func makeTranscriber(modelDirectory: URL, arch: MoonshineNativeModelArch) async throws -> any MoonshineNativeTranscribing {
        lock.withLock {
            count += 1
        }
        return FakeNativeTranscriber(
            stream: FakeNativeStream(finishTranscript: MoonshineNativeTranscript(lines: []))
        )
    }
}

private struct FakeNativeError: Error {}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
