@testable import LocalWisprCore
import Foundation
import Testing

@Test
func whisperServerDiscoveryUsesDefaultLoopbackEndpointWhenReachable() {
    let engine = WhisperServerEngine.discover(environment: [:], isReachable: { _ in true })

    #expect(engine?.endpoint.absoluteString == "http://127.0.0.1:8178/inference")
}

@Test
func whisperServerDiscoverySkipsDefaultEndpointWhenUnavailable() {
    let engine = WhisperServerEngine.discover(environment: [:], isReachable: { _ in false })

    #expect(engine == nil)
}

@Test
func whisperServerDiscoveryCanBeDisabled() {
    let engine = WhisperServerEngine.discover(environment: [
        "LOCAL_WISPR_DISABLE_WHISPER_SERVER": "1"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func whisperServerDiscoveryUsesDefaultLoopbackEndpointWhenExplicitlyEnabled() {
    let engine = WhisperServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "whisper-server"
    ], isReachable: { _ in false })

    #expect(engine?.endpoint.absoluteString == "http://127.0.0.1:8178/inference")
}

@Test
func whisperServerDiscoveryNormalizesConfiguredLoopbackRootURL() {
    let engine = WhisperServerEngine.discover(environment: [
        "LOCAL_WISPR_WHISPER_SERVER_URL": "http://localhost:9001"
    ], isReachable: { _ in false })

    #expect(engine?.endpoint.absoluteString == "http://localhost:9001/inference")
}

@Test
func whisperServerDiscoveryRejectsNonLoopbackEndpoint() {
    let engine = WhisperServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "whisper-server",
        "LOCAL_WISPR_WHISPER_SERVER_URL": "http://192.168.1.50:8178/inference"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func whisperServerDiscoveryHonorsExplicitNonServerEngine() {
    let engine = WhisperServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "whisper-cli",
        "LOCAL_WISPR_WHISPER_SERVER_URL": "http://127.0.0.1:8178/inference"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func whisperServerResponseParserReadsJSONText() {
    let data = #"{"text":" [00:00:00.000 --> 00:00:01.000] hello server\n"}"#
        .data(using: .utf8)!

    let cleaned = WhisperServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "hello server")
}

@Test
func whisperServerResponseParserReadsSegmentJSON() {
    let data = #"{"segments":[{"text":"hello"},{"text":"warm worker"}]}"#
        .data(using: .utf8)!

    let cleaned = WhisperServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "hello warm worker")
}

@Test
func whisperServerResponseParserIgnoresJSONWithoutTranscriptText() {
    let data = #"{"error":"server failed"}"#.data(using: .utf8)!

    let cleaned = WhisperServerEngine.cleanedTranscript(from: data)

    #expect(cleaned.isEmpty)
}

@Test
func whisperServerResponseParserFallsBackToPlainText() {
    let data = "[00:00:00.000 --> 00:00:01.000] plain text".data(using: .utf8)!

    let cleaned = WhisperServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "plain text")
}
