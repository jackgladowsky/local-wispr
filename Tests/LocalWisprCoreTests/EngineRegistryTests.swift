@testable import LocalWisprCore
import Foundation
import Testing

@Test
func engineRegistryPrefersNativeMoonshineWithServerFallback() {
    let native = MoonshineNativeEngine(
        modelDirectory: URL(fileURLWithPath: "/tmp/native-model"),
        runtime: RegistryFakeRuntime()
    )
    let server = MoonshineServerEngine(endpoint: URL(string: "http://127.0.0.1:8179/transcribe")!)

    let engine = EngineRegistry.makeSTTEngine(
        preferredMoonshineNative: native,
        preferredMoonshineServer: server
    )

    #expect(engine.name == "Moonshine native en/medium-streaming with Moonshine server 127.0.0.1:8179 fallback")
}

@Test
func engineRegistryUsesServerWhenNativeUnavailable() {
    let server = MoonshineServerEngine(endpoint: URL(string: "http://127.0.0.1:8179/transcribe")!)

    let engine = EngineRegistry.makeSTTEngine(
        preferredMoonshineNative: nil,
        preferredMoonshineServer: server
    )

    #expect(engine.name == "Moonshine server 127.0.0.1:8179")
}

@Test
func fallbackSTTEngineStartsStreamingSessionFromFallbackWhenPrimaryStartThrows() async throws {
    let fallback = RegistryRecordingStreamingEngine()
    let engine = FallbackSTTEngine(
        primary: RegistryThrowingStreamingEngine(),
        fallback: fallback
    )

    let session = try await engine.startStreamingSession(startedAt: Date())

    #expect(session.name == "registry recording streaming")
}

private struct RegistryFakeRuntime: MoonshineNativeRuntime {
    func makeTranscriber(modelDirectory: URL, arch: MoonshineNativeModelArch) async throws -> any MoonshineNativeTranscribing {
        RegistryFakeTranscriber()
    }
}

private struct RegistryFakeTranscriber: MoonshineNativeTranscribing {
    func transcribe(samples: [Float], sampleRate: Int32) async throws -> MoonshineNativeTranscript {
        MoonshineNativeTranscript(lines: [])
    }

    func startStream(updateInterval: TimeInterval) async throws -> any MoonshineNativeStreaming {
        RegistryFakeStream()
    }
}

private struct RegistryFakeStream: MoonshineNativeStreaming {
    func append(samples: [Float], sampleRate: Int32) async throws {}

    func finish() async throws -> MoonshineNativeTranscript {
        MoonshineNativeTranscript(lines: [])
    }

    func cancel() async {}
}

private struct RegistryThrowingStreamingEngine: StreamingSTTEngine {
    let name = "registry throwing"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        throw RegistryStreamingError()
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        throw RegistryStreamingError()
    }
}

private struct RegistryRecordingStreamingEngine: StreamingSTTEngine {
    let name = "registry recording"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        Transcript(text: "fallback", confidence: nil, segments: [])
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        RegistryRecordingStreamingSession()
    }
}

private struct RegistryRecordingStreamingSession: StreamingSTTSession {
    let name = "registry recording streaming"

    func append(_ buffer: StreamingAudioBuffer) async throws {}

    func finish(endedAt: Date) async throws -> Transcript {
        Transcript(text: "done", confidence: nil, segments: [])
    }

    func cancel() async {}
}

private struct RegistryStreamingError: Error {}
