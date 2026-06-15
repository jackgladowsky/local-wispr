import Foundation

struct OllamaRewriteEngine: RewriteEngine {
    let model: String
    let endpoint: URL

    var name: String {
        "Ollama \(model)"
    }

    static func discover() -> OllamaRewriteEngine? {
        guard ExecutableLocator.find("ollama") != nil else { return nil }

        let model = ProcessInfo.processInfo.environment["LOCAL_WISPR_OLLAMA_MODEL"] ?? "qwen3:0.6b"
        return OllamaRewriteEngine(
            model: model,
            endpoint: URL(string: "http://127.0.0.1:11434/api/generate")!
        )
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(
                model: model,
                prompt: Self.prompt(for: transcript.text),
                stream: false,
                think: false,
                keep_alive: "10m",
                options: .init(temperature: 0.1, num_predict: Self.numPredict(for: transcript.text))
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalWisprError.cleanupFailed("Ollama returned a non-200 response")
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let cleaned = decoded.response
            .replacingOccurrences(of: #"<think>.*?</think>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw LocalWisprError.cleanupFailed("Ollama returned empty text")
        }

        return CleanedText(text: cleaned, engineName: name)
    }

    private static func prompt(for transcript: String) -> String {
        CleanupPrompt.compact(for: transcript)
    }

    private static func numPredict(for transcript: String) -> Int {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["LOCAL_WISPR_CLEANUP_NUM_PREDICT"].flatMap(Int.init), override > 0 {
            return override
        }

        return min(192, max(48, transcript.count / 3 + 32))
    }
}

private struct GenerateRequest: Encodable {
    struct Options: Encodable {
        let temperature: Double
        let num_predict: Int
    }

    let model: String
    let prompt: String
    let stream: Bool
    let think: Bool
    let keep_alive: String
    let options: Options
}

private struct GenerateResponse: Decodable {
    let response: String
}
