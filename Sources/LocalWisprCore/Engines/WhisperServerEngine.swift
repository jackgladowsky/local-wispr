import Foundation

struct WhisperServerEngine: STTEngine {
    let endpoint: URL

    var name: String {
        let host = endpoint.host ?? "loopback"
        let port = endpoint.port.map { ":\($0)" } ?? ""
        return "whisper.cpp server \(host)\(port)"
    }

    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> WhisperServerEngine? {
        discover(environment: environment, isReachable: defaultReachabilityCheck)
    }

    static func discover(
        environment: [String: String],
        isReachable: (URL) -> Bool
    ) -> WhisperServerEngine? {
        let engine = environment["LOCAL_WISPR_STT_ENGINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let configuredURL = environment["LOCAL_WISPR_WHISPER_SERVER_URL"]
            ?? environment["LOCAL_WISPR_WHISPER_SERVER_ENDPOINT"]

        if let engine, !["whisper-server", "server"].contains(engine) {
            return nil
        }

        if flag("LOCAL_WISPR_DISABLE_WHISPER_SERVER", in: environment) {
            return nil
        }

        let endpointString = configuredURL ?? "http://127.0.0.1:8178/inference"
        guard let endpoint = URL(string: endpointString) else {
            return nil
        }

        let normalizedEndpoint = normalizedInferenceEndpoint(endpoint)
        guard allowsEndpoint(normalizedEndpoint) else {
            return nil
        }

        if engine == nil, configuredURL == nil, !isReachable(serverRoot(for: normalizedEndpoint)) {
            return nil
        }

        return WhisperServerEngine(endpoint: normalizedEndpoint)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        guard let audioURL = request.audioURL else {
            throw LocalWisprError.missingAudioRecording
        }

        let boundary = "LocalWisprBoundary-\(UUID().uuidString)"
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = Self.requestTimeout(for: request.duration)
        httpRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try Self.multipartBody(
            audioURL: audioURL,
            boundary: boundary,
            fields: [
                "response_format": "json",
                "temperature": "0.0",
                "temperature_inc": "0.2"
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = Int32((response as? HTTPURLResponse)?.statusCode ?? -1)
            let body = String(decoding: data, as: UTF8.self)
            throw LocalWisprError.processFailed(
                command: "whisper-server",
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

    static func cleanedTranscript(from responseData: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: responseData) {
            return WhisperCLIEngine.cleanedTranscript(from: textFromJSONObject(object) ?? "")
        }

        return WhisperCLIEngine.cleanedTranscript(from: String(decoding: responseData, as: UTF8.self))
    }

    static func normalizedInferenceEndpoint(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/inference"
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
        let result = ReachabilityResult()
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

    private static func requestTimeout(for duration: TimeInterval) -> TimeInterval {
        if let override = ProcessInfo.processInfo.environment["LOCAL_WISPR_WHISPER_SERVER_TIMEOUT_SECONDS"].flatMap(TimeInterval.init), override > 0 {
            return override
        }

        return max(2, min(15, duration * 3))
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
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

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

        return nil
    }
}

private final class ReachabilityResult: @unchecked Sendable {
    var isReachable = false
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
