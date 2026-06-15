import Foundation

struct LlamaServerRewriteEngine: RewriteEngine {
    let endpoint: URL

    var name: String {
        "llama.cpp server"
    }

    static func discover() -> LlamaServerRewriteEngine? {
        let environment = ProcessInfo.processInfo.environment
        let engine = environment["LOCAL_WISPR_REWRITE_ENGINE"]?.lowercased()
        let configuredURL = environment["LOCAL_WISPR_LLAMA_SERVER_URL"]
            ?? environment["LOCAL_WISPR_LLAMA_SERVER_ENDPOINT"]

        guard engine == "llama-server" || configuredURL != nil else {
            return nil
        }

        let endpoint = URL(string: configuredURL ?? "http://127.0.0.1:8080/completion")
            ?? URL(string: "http://127.0.0.1:8080/completion")!

        return LlamaServerRewriteEngine(endpoint: normalizedCompletionEndpoint(endpoint))
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CompletionRequest(
                prompt: CleanupPrompt.compact(for: transcript.text),
                n_predict: Self.numPredict(for: transcript.text),
                temperature: 0.1,
                cache_prompt: true,
                stream: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalWisprError.cleanupFailed("llama.cpp server returned a non-200 response")
        }

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        let cleaned = decoded.content
            .replacingOccurrences(of: #"<think>.*?</think>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw LocalWisprError.cleanupFailed("llama.cpp server returned empty text")
        }

        return CleanedText(text: cleaned, engineName: name)
    }

    private static func normalizedCompletionEndpoint(_ url: URL) -> URL {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return url.appendingPathComponent("completion")
        }

        return url
    }

    private static func numPredict(for transcript: String) -> Int {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["LOCAL_WISPR_CLEANUP_NUM_PREDICT"].flatMap(Int.init), override > 0 {
            return override
        }

        return min(192, max(48, transcript.count / 3 + 32))
    }
}

private struct CompletionRequest: Encodable {
    let prompt: String
    let n_predict: Int
    let temperature: Double
    let cache_prompt: Bool
    let stream: Bool
}

private struct CompletionResponse: Decodable {
    let content: String
}
