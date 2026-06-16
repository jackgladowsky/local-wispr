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
        let normalizedEndpoint = normalizedCompletionEndpoint(endpoint)

        guard allowsEndpoint(normalizedEndpoint, environment: environment) else {
            return nil
        }

        return LlamaServerRewriteEngine(endpoint: normalizedEndpoint)
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
                temperature: 0.0,
                cache_prompt: true,
                stream: false,
                stop: ["<|im_end|>", "<|endoftext|>"]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalWisprError.cleanupFailed("llama.cpp server returned a non-200 response")
        }

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        let cleaned = Self.polish(decoded.content)

        guard !cleaned.isEmpty else {
            throw LocalWisprError.cleanupFailed("llama.cpp server returned empty text")
        }

        return CleanedText(text: cleaned, engineName: name)
    }

    private static func polish(_ content: String) -> String {
        var text = content
            .replacingOccurrences(of: #"<think>.*?</think>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(
            of: #"(?is)^\s*(sure,?\s*)?(here'?s\s+(the\s+)?)?(final\s+)?(cleaned\s+)?(text|output)\s*:\s*"#,
            with: "",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"(?i)(?<![\p{L}])(um+|uh+|erm+|ah+)(?![\p{L}])[,\s]*"#,
            with: "",
            options: .regularExpression
        )

        let replacements: [(String, String)] = [
            (#"(?<![\p{L}])i(?![\p{L}])"#, "I"),
            (#"(?i)(?<![\p{L}])john(?![\p{L}])"#, "John"),
            (#"(?i)(?<![\p{L}])monday(?![\p{L}])"#, "Monday"),
            (#"(?i)(?<![\p{L}])tuesday(?![\p{L}])"#, "Tuesday"),
            (#"(?i)(?<![\p{L}])wednesday(?![\p{L}])"#, "Wednesday"),
            (#"(?i)(?<![\p{L}])thursday(?![\p{L}])"#, "Thursday"),
            (#"(?i)(?<![\p{L}])friday(?![\p{L}])"#, "Friday"),
            (#"(?i)(?<![\p{L}])saturday(?![\p{L}])"#, "Saturday"),
            (#"(?i)(?<![\p{L}])sunday(?![\p{L}])"#, "Sunday")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedCompletionEndpoint(_ url: URL) -> URL {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return url.appendingPathComponent("completion")
        }

        return url
    }

    private static func allowsEndpoint(_ url: URL, environment: [String: String]) -> Bool {
        if environment["LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA"] == "1" {
            return true
        }

        let host = (url.host ?? "").lowercased()
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    private static func numPredict(for transcript: String) -> Int {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["LOCAL_WISPR_CLEANUP_NUM_PREDICT"].flatMap(Int.init), override > 0 {
            return override
        }

        return min(192, max(38, transcript.count / 8 + 16))
    }
}

private struct CompletionRequest: Encodable {
    let prompt: String
    let n_predict: Int
    let temperature: Double
    let cache_prompt: Bool
    let stream: Bool
    let stop: [String]
}

private struct CompletionResponse: Decodable {
    let content: String
}
