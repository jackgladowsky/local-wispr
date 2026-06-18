@testable import LocalWisprCore
import Foundation
import Testing

@Test
func moonshineServerDiscoveryUsesDefaultLoopbackEndpointWhenReachable() {
    let engine = MoonshineServerEngine.discover(environment: [:], isReachable: { _ in true })

    #expect(engine?.endpoint.absoluteString == "http://127.0.0.1:8179/transcribe")
}

@Test
func moonshineServerDiscoverySkipsDefaultEndpointWhenUnavailable() {
    let engine = MoonshineServerEngine.discover(environment: [:], isReachable: { _ in false })

    #expect(engine == nil)
}

@Test
func moonshineServerDiscoveryCanBeDisabled() {
    let engine = MoonshineServerEngine.discover(environment: [
        "LOCAL_WISPR_DISABLE_MOONSHINE_SERVER": "1"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func moonshineServerDiscoveryUsesDefaultLoopbackEndpointWhenExplicitlyEnabled() {
    let engine = MoonshineServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "moonshine"
    ], isReachable: { _ in false })

    #expect(engine?.endpoint.absoluteString == "http://127.0.0.1:8179/transcribe")
}

@Test
func moonshineServerDiscoveryNormalizesConfiguredLoopbackRootURL() {
    let engine = MoonshineServerEngine.discover(environment: [
        "LOCAL_WISPR_MOONSHINE_SERVER_URL": "http://localhost:9010"
    ], isReachable: { _ in false })

    #expect(engine?.endpoint.absoluteString == "http://localhost:9010/transcribe")
}

@Test
func moonshineServerDiscoveryRejectsNonLoopbackEndpoint() {
    let engine = MoonshineServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "moonshine",
        "LOCAL_WISPR_MOONSHINE_SERVER_URL": "http://192.168.1.50:8179/transcribe"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func moonshineServerDiscoveryHonorsExplicitNonMoonshineEngine() {
    let engine = MoonshineServerEngine.discover(environment: [
        "LOCAL_WISPR_STT_ENGINE": "custom",
        "LOCAL_WISPR_MOONSHINE_SERVER_URL": "http://127.0.0.1:8179/transcribe"
    ], isReachable: { _ in true })

    #expect(engine == nil)
}

@Test
func moonshineServerResponseParserReadsJSONText() {
    let data = #"{"text":"hello moonshine"}"#.data(using: .utf8)!

    let cleaned = MoonshineServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "hello moonshine")
}

@Test
func moonshineServerResponseParserReadsNestedResultText() {
    let data = #"{"result":{"text":"nested moonshine"}}"#.data(using: .utf8)!

    let cleaned = MoonshineServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "nested moonshine")
}

@Test
func moonshineServerResponseParserReadsSegmentArray() {
    let data = #"[{"text":"fast"},{"text":"speech"}]"#.data(using: .utf8)!

    let cleaned = MoonshineServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "fast speech")
}

@Test
func moonshineServerResponseParserFallsBackToPlainText() {
    let data = "plain moonshine text".data(using: .utf8)!

    let cleaned = MoonshineServerEngine.cleanedTranscript(from: data)

    #expect(cleaned == "plain moonshine text")
}
