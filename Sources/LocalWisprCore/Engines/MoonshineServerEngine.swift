import Foundation

struct MoonshineServerEngine: StreamingSTTEngine {
    let endpoint: URL

    var name: String {
        let host = endpoint.host ?? "loopback"
        let port = endpoint.port.map { ":\($0)" } ?? ""
        return "Moonshine server \(host)\(port)"
    }

    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> MoonshineServerEngine? {
        discover(environment: environment, isReachable: defaultReachabilityCheck)
    }

    static func discover(
        environment: [String: String],
        isReachable: (URL) -> Bool
    ) -> MoonshineServerEngine? {
        let engine = environment["LOCAL_WISPR_STT_ENGINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let configuredURL = environment["LOCAL_WISPR_MOONSHINE_SERVER_URL"]
            ?? environment["LOCAL_WISPR_MOONSHINE_SERVER_ENDPOINT"]

        if let engine, !["moonshine", "moonshine-server"].contains(engine) {
            return nil
        }

        if flag("LOCAL_WISPR_DISABLE_MOONSHINE_SERVER", in: environment) {
            return nil
        }

        let endpointString = configuredURL ?? "http://127.0.0.1:8179/transcribe"
        guard let endpointURL = URL(string: endpointString) else {
            return nil
        }

        let normalizedEndpoint = normalizedTranscriptionEndpoint(endpointURL)
        guard allowsEndpoint(normalizedEndpoint) else {
            return nil
        }

        if engine == nil, configuredURL == nil, !isReachable(serverRoot(for: normalizedEndpoint)) {
            return nil
        }

        return MoonshineServerEngine(endpoint: normalizedEndpoint)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        guard let audioURL = request.audioURL else {
            throw LocalWisprError.missingAudioRecording
        }

        let boundary = "LocalWisprMoonshineBoundary-\(UUID().uuidString)"
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = Self.requestTimeout(for: request.duration)
        httpRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try Self.multipartBody(
            audioURL: audioURL,
            boundary: boundary,
            fields: [
                "response_format": "json"
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = Int32((response as? HTTPURLResponse)?.statusCode ?? -1)
            let body = String(decoding: data, as: UTF8.self)
            throw LocalWisprError.processFailed(
                command: "moonshine-server",
                status: status,
                stderr: body.isEmpty ? "non-200 HTTP response" : body
            )
        }

        let text = Self.cleanedTranscript(from: data)
        guard !text.isEmpty else {
            throw LocalWisprError.emptyTranscript
        }

        return Transcript(
            text: text,
            confidence: nil,
            segments: [
                .init(text: text, startTime: 0, endTime: request.duration)
            ]
        )
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        let data = try await Self.sendJSONRequest(
            url: Self.serverEndpoint(for: endpoint, path: "/sessions"),
            method: "POST",
            payload: [:],
            timeout: 2
        )

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LocalWisprError.processFailed(
                command: "moonshine-server",
                status: -1,
                stderr: "streaming session response did not include an id"
            )
        }

        return MoonshineStreamingServerSession(
            id: id,
            endpoint: endpoint,
            startedAt: startedAt,
            engineName: name
        )
    }

    static func cleanedTranscript(from responseData: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: responseData) {
            return TranscriptTextCleaner.cleanedTranscript(from: textFromJSONObject(object) ?? "")
        }

        return TranscriptTextCleaner.cleanedTranscript(from: String(decoding: responseData, as: UTF8.self))
    }

    static func normalizedTranscriptionEndpoint(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/transcribe"
        }

        return components.url ?? url
    }

    static func allowsEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }

        let host = (url.host ?? "").lowercased()
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    static func serverEndpoint(for endpoint: URL, path: String) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint
        }

        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.query = nil
        components.fragment = nil
        return components.url ?? endpoint
    }

    static func serverRoot(for endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url ?? endpoint
    }

    static func defaultReachabilityCheck(_ url: URL) -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.2

        let semaphore = DispatchSemaphore(value: 0)
        let result = MoonshineReachabilityResult()
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error == nil, response is HTTPURLResponse {
                result.isReachable = true
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 0.25) == .timedOut {
            task.cancel()
        }
        return result.isReachable
    }

    fileprivate static func sendJSONRequest(
        url: URL,
        method: String,
        payload: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = Int32((response as? HTTPURLResponse)?.statusCode ?? -1)
            let body = String(decoding: data, as: UTF8.self)
            throw LocalWisprError.processFailed(
                command: "moonshine-server",
                status: status,
                stderr: body.isEmpty ? "non-2xx HTTP response" : body
            )
        }

        return data
    }

    private static func requestTimeout(for duration: TimeInterval) -> TimeInterval {
        if let override = ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_SERVER_TIMEOUT_SECONDS"].flatMap(TimeInterval.init), override > 0 {
            return override
        }

        return max(2, min(15, duration * 2))
    }

    private static func flag(_ name: String, in environment: [String: String]) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }

    private static func multipartBody(
        audioURL: URL,
        boundary: String,
        fields: [String: String]
    ) throws -> Data {
        var body = Data()

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n"
        )
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        body.appendUTF8("\r\n")
        body.appendUTF8("--\(boundary)--\r\n")

        return body
    }

    private static func textFromJSONObject(_ object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }

            if let text = dictionary["transcription"] as? String {
                return text
            }

            if
                let result = dictionary["result"] as? [String: Any],
                let text = result["text"] as? String
            {
                return text
            }

            if let segments = dictionary["segments"] as? [[String: Any]] {
                let text = segments
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
                return text.isEmpty ? nil : text
            }
        }

        if let array = object as? [[String: Any]] {
            let text = array
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }

        return nil
    }
}

private struct MoonshineStreamingServerSession: StreamingSTTSession {
    let id: String
    let endpoint: URL
    let startedAt: Date
    let engineName: String

    var name: String {
        "\(engineName) streaming"
    }

    func append(_ buffer: StreamingAudioBuffer) async throws {
        guard !buffer.samples.isEmpty else { return }

        _ = try await MoonshineServerEngine.sendJSONRequest(
            url: sessionEndpoint("audio"),
            method: "POST",
            payload: [
                "sample_rate": buffer.sampleRate,
                "samples": buffer.samples.map(Double.init)
            ],
            timeout: 2
        )
    }

    func finish(endedAt: Date) async throws -> Transcript {
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let data = try await MoonshineServerEngine.sendJSONRequest(
            url: sessionEndpoint("finish"),
            method: "POST",
            payload: [:],
            timeout: max(2, min(10, duration + 1))
        )

        let text = MoonshineServerEngine.cleanedTranscript(from: data)
        guard !text.isEmpty else {
            throw LocalWisprError.emptyTranscript
        }

        return Transcript(
            text: text,
            confidence: nil,
            segments: [
                .init(text: text, startTime: 0, endTime: duration)
            ]
        )
    }

    func cancel() async {
        _ = try? await MoonshineServerEngine.sendJSONRequest(
            url: sessionEndpoint(nil),
            method: "DELETE",
            payload: nil,
            timeout: 1
        )
    }

    private func sessionEndpoint(_ action: String?) -> URL {
        var path = "/sessions/\(id)"
        if let action {
            path += "/\(action)"
        }
        return MoonshineServerEngine.serverEndpoint(for: endpoint, path: path)
    }
}

private final class MoonshineReachabilityResult: @unchecked Sendable {
    var isReachable = false
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
