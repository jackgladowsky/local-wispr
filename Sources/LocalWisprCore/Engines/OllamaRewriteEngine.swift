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
                options: .init(temperature: 0.1, num_predict: 512)
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

        return CleanedText(text: cleaned)
    }

    private static func prompt(for transcript: String) -> String {
        """
        You are a local dictation cleanup engine.

        Rewrite the transcript into clean, natural text.

        Rules:
        - Preserve the user's meaning.
        - Do not add facts, names, dates, links, or commitments.
        - Fix punctuation and capitalization.
        - Remove filler words when they do not matter.
        - Keep names, emails, URLs, code, numbers, and product names as close to the transcript as possible.
        - If a word is uncertain, prefer the transcript instead of inventing.
        - Preserve profanity and sensitive wording when the user said it.
        - Preserve line breaks and list structure when clearly dictated.
        - Do not explain your changes.
        - Return only the cleaned text.

        Transcript:
        <<<
        \(transcript)
        >>>
        """
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
    let options: Options
}

private struct GenerateResponse: Decodable {
    let response: String
}
