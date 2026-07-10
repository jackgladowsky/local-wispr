@testable import LocalWisprCore
import Foundation
import Testing

@Test
func openAICompatibleRewritePostsChatCompletionRequestAndReturnsCleanedText() async throws {
    let recorder = RequestRecorder()
    let response = #"{"choices":[{"message":{"content":"Cleaned output."}}]}"#.data(using: .utf8)!
    let engine = OpenAICompatibleRewriteEngine(
        endpoint: URL(string: "http://127.0.0.1:8080/v1/chat/completions")!,
        model: "llama-fast-cleanup",
        apiKey: "test-key",
        context: "App: Notes",
        dataLoader: StubHTTPDataLoader(data: response, recorder: recorder)
    )

    let cleaned = try await engine.rewrite(
        Transcript(text: "um hello world", confidence: nil, segments: [])
    )

    #expect(cleaned.text == "Cleaned output.")
    #expect(cleaned.engineName == "OpenAI-compatible cleanup llama-fast-cleanup at 127.0.0.1")

    let request = try #require(recorder.request)
    #expect(request.url?.absoluteString == "http://127.0.0.1:8080/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

    let body = try #require(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["model"] as? String == "llama-fast-cleanup")
    #expect(json?["stream"] as? Bool == false)
    #expect(json?["temperature"] as? Double == 0)

    let messages = try #require(json?["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] == "system")
    #expect(messages[0]["content"]?.contains("Return only the final cleaned text") == true)
    #expect(messages[1]["content"]?.contains("Context:\nApp: Notes") == true)
    #expect(messages[1]["content"]?.contains("Transcript:\num hello world") == true)
}

@Test
func openAICompatibleRewriteAcceptsLegacyTextChoiceAndPolishesPreamble() async throws {
    let response = #"{"choices":[{"text":"Final cleaned text: \"Hello world.\""}]}"#.data(using: .utf8)!
    let engine = OpenAICompatibleRewriteEngine(
        endpoint: URL(string: "http://127.0.0.1:8080/v1/chat/completions")!,
        model: "local-cleanup",
        dataLoader: StubHTTPDataLoader(data: response)
    )

    let cleaned = try await engine.rewrite(
        Transcript(text: "hello world", confidence: nil, segments: [])
    )

    #expect(cleaned.text == "Hello world.")
}

@Test
func openAICompatibleDiscoveryNormalizesLocalRootEndpoint() {
    let engine = OpenAICompatibleRewriteEngine.discover(environment: [
        "LOCAL_WISPR_REWRITE_ENGINE": "smart-hosted",
        "LOCAL_WISPR_SMART_CLEANUP_URL": "http://127.0.0.1:8080",
        "LOCAL_WISPR_SMART_CLEANUP_MODEL": "tiny-cleanup"
    ])

    #expect(engine?.endpoint.absoluteString == "http://127.0.0.1:8080/v1/chat/completions")
    #expect(engine?.model == "tiny-cleanup")
}

@Test
func openAICompatibleDiscoveryRequiresExplicitRemoteOptInAndAPIKey() {
    #expect(OpenAICompatibleRewriteEngine.discover(environment: [
        "LOCAL_WISPR_SMART_CLEANUP_URL": "https://api.example.com/v1/chat/completions"
    ]) == nil)

    #expect(OpenAICompatibleRewriteEngine.discover(environment: [
        "LOCAL_WISPR_REWRITE_ENGINE": "smart-hosted",
        "LOCAL_WISPR_SMART_CLEANUP_URL": "https://api.example.com/v1/chat/completions"
    ]) == nil)

    let engine = OpenAICompatibleRewriteEngine.discover(environment: [
        "LOCAL_WISPR_REWRITE_ENGINE": "smart-hosted",
        "LOCAL_WISPR_SMART_CLEANUP_URL": "https://api.example.com/v1/chat/completions",
        "LOCAL_WISPR_SMART_CLEANUP_API_KEY": "secret",
        "LOCAL_WISPR_SMART_CLEANUP_MODEL": "fast-hosted"
    ])

    #expect(engine?.endpoint.absoluteString == "https://api.example.com/v1/chat/completions")
    #expect(engine?.model == "fast-hosted")
}

@Test
func fallbackRewriteCanDisableFastLocalShortCircuitForSmartCleanup() async throws {
    let engine = FallbackRewriteEngine(
        primary: FixedRewriteEngine(name: "Smart", output: "smart output"),
        fallback: FixedRewriteEngine(name: "Fallback", output: "fallback output"),
        usesFastLocalShortCircuit: false
    )

    let cleaned = try await engine.rewrite(
        Transcript(text: "hello world", confidence: nil, segments: [])
    )

    #expect(cleaned.text == "smart output")
    #expect(cleaned.engineName == "Smart")
}

private struct StubHTTPDataLoader: HTTPDataLoading {
    let data: Data
    var statusCode = 200
    var recorder: RequestRecorder?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorder?.record(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequest: URLRequest?

    var request: URLRequest? {
        lock.withLock { recordedRequest }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            recordedRequest = request
        }
    }
}

private struct FixedRewriteEngine: RewriteEngine {
    let name: String
    let output: String

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        CleanedText(text: output, engineName: name)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
