import Foundation

struct OpenAICompatibleRewriteEngine: RewriteEngine {
    let endpoint: URL
    let model: String
    let apiKey: String?
    let timeout: TimeInterval
    let context: String?
    let dataLoader: any HTTPDataLoading

    var name: String {
        if Self.isLoopback(endpoint) {
            "OpenAI-compatible cleanup \(model) at \(endpoint.host ?? "localhost")"
        } else {
            "Hosted cleanup \(model)"
        }
    }

    init(
        endpoint: URL,
        model: String,
        apiKey: String? = nil,
        timeout: TimeInterval = 1.2,
        context: String? = nil,
        dataLoader: any HTTPDataLoading = URLSession.shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.context = context
        self.dataLoader = dataLoader
    }

    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> OpenAICompatibleRewriteEngine? {
        let configuredEngine = environment["LOCAL_WISPR_REWRITE_ENGINE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let endpointValue = environment["LOCAL_WISPR_SMART_CLEANUP_URL"]
            ?? environment["LOCAL_WISPR_SMART_CLEANUP_ENDPOINT"]
            ?? environment["LOCAL_WISPR_OPENAI_COMPATIBLE_URL"]
            ?? environment["LOCAL_WISPR_OPENAI_COMPATIBLE_ENDPOINT"]
            ?? environment["OPENAI_BASE_URL"]

        let isExplicitEngine = [
            "smart-hosted",
            "hosted-cleanup",
            "openai-compatible",
            "openai-compatible-cleanup"
        ].contains(configuredEngine)

        guard isExplicitEngine || endpointValue != nil else { return nil }

        let endpoint = normalizedChatCompletionsEndpoint(
            URL(string: endpointValue ?? "http://127.0.0.1:8080/v1/chat/completions")
                ?? URL(string: "http://127.0.0.1:8080/v1/chat/completions")!
        )

        guard allowsEndpoint(endpoint, environment: environment, isExplicitEngine: isExplicitEngine) else {
            return nil
        }

        let model = environment["LOCAL_WISPR_SMART_CLEANUP_MODEL"]
            ?? environment["LOCAL_WISPR_OPENAI_COMPATIBLE_MODEL"]
            ?? environment["OPENAI_MODEL"]
            ?? "local-cleanup"
        let apiKey = environment["LOCAL_WISPR_SMART_CLEANUP_API_KEY"]
            ?? environment["LOCAL_WISPR_OPENAI_COMPATIBLE_API_KEY"]
            ?? environment["OPENAI_API_KEY"]
        let timeout = environment["LOCAL_WISPR_SMART_CLEANUP_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.1, $0) }
            ?? 1.2
        let context = environment["LOCAL_WISPR_SMART_CLEANUP_CONTEXT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return OpenAICompatibleRewriteEngine(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey?.nilIfEmpty,
            timeout: timeout,
            context: context
        )
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalWisprError.emptyTranscript }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: Self.messages(for: text, context: context),
                temperature: 0,
                max_tokens: Self.maxTokens(for: text),
                stream: false
            )
        )

        let (data, response) = try await dataLoader.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LocalWisprError.cleanupFailed("OpenAI-compatible cleanup returned HTTP \(status)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let cleaned = Self.polish(decoded.primaryContent)
        guard !cleaned.isEmpty else {
            throw LocalWisprError.cleanupFailed("OpenAI-compatible cleanup returned empty text")
        }

        return CleanedText(text: cleaned, engineName: name)
    }

    static func messages(for transcript: String, context: String?) -> [ChatMessage] {
        var user = "Transcript:\n\(transcript)"
        if let context, !context.isEmpty {
            user = "Context:\n\(context)\n\n" + user
        }

        return [
            ChatMessage(
                role: "system",
                content: """
                You are Local Wispr's dictation cleanup layer. Return only the final cleaned text.
                Preserve the user's meaning, voice, order, names, dates, numbers, URLs, emails, code symbols, file paths, and task items.
                Fix punctuation, capitalization, spacing, obvious speech-recognition errors, and light grammar.
                Remove filler words and false starts when they are clearly not intended: um, uh, erm, ah, you know, I mean.
                Apply spoken edit commands such as scratch that, delete that, new line, and new paragraph when unambiguous.
                Do not summarize, answer, explain, add facts, or wrap the result in quotes.
                """
            ),
            ChatMessage(role: "user", content: user)
        ]
    }

    static func maxTokens(for transcript: String) -> Int {
        min(512, max(48, transcript.count / 3 + 32))
    }

    static func normalizedChatCompletionsEndpoint(_ url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            return url.appendingPathComponent("v1/chat/completions")
        }
        if trimmedPath == "v1" {
            return url.appendingPathComponent("chat/completions")
        }
        return url
    }

    static func allowsEndpoint(
        _ url: URL,
        environment: [String: String],
        isExplicitEngine: Bool
    ) -> Bool {
        if isLoopback(url) { return true }

        let hasExplicitRemoteOptIn = isExplicitEngine
            || environment["LOCAL_WISPR_ALLOW_REMOTE_SMART_CLEANUP"] == "1"
        let hasAPIKey = [
            environment["LOCAL_WISPR_SMART_CLEANUP_API_KEY"],
            environment["LOCAL_WISPR_OPENAI_COMPATIBLE_API_KEY"],
            environment["OPENAI_API_KEY"]
        ]
            .compactMap { $0?.nilIfEmpty }
            .isEmpty == false

        return hasExplicitRemoteOptIn && hasAPIKey
    }

    static func polish(_ content: String) -> String {
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

        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text.removeFirst()
            text.removeLast()
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLoopback(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }
}

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

struct ChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    var primaryContent: String {
        choices.first?.message?.content ?? choices.first?.text ?? ""
    }

    struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    struct Message: Decodable {
        let content: String
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
