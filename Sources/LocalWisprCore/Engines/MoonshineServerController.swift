import Foundation

final class MoonshineServerController {
    let engine: MoonshineServerEngine

    private let pythonURL: URL
    private let scriptURL: URL
    private let host: String
    private let port: Int
    private let backend: String
    private let model: String
    private let language: String
    private let voiceArch: String
    private let device: String?
    private let torchDType: String?
    private let maxNewTokens: String?
    private let attentionImplementation: String?
    private let shouldPreload: Bool
    private let logURL: URL
    private let environment: [String: String]

    private var process: Process?
    private var logHandle: FileHandle?

    init(
        engine: MoonshineServerEngine,
        pythonURL: URL,
        scriptURL: URL,
        host: String,
        port: Int,
        backend: String,
        model: String,
        language: String,
        voiceArch: String,
        device: String?,
        torchDType: String?,
        maxNewTokens: String?,
        attentionImplementation: String?,
        shouldPreload: Bool,
        logURL: URL,
        environment: [String: String]
    ) {
        self.engine = engine
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
        self.host = host
        self.port = port
        self.backend = backend
        self.model = model
        self.language = language
        self.voiceArch = voiceArch
        self.device = device
        self.torchDType = torchDType
        self.maxNewTokens = maxNewTokens
        self.attentionImplementation = attentionImplementation
        self.shouldPreload = shouldPreload
        self.logURL = logURL
        self.environment = environment
    }

    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> MoonshineServerController? {
        if flag("LOCAL_WISPR_DISABLE_MOONSHINE_SERVER", in: environment)
            || flag("LOCAL_WISPR_DISABLE_MANAGED_MOONSHINE_SERVER", in: environment) {
            return nil
        }

        let requestedEngine = environment["LOCAL_WISPR_STT_ENGINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let requestedEngine, !["moonshine", "moonshine-server"].contains(requestedEngine) {
            return nil
        }

        let host = environment["LOCAL_WISPR_MOONSHINE_HOST"] ?? "127.0.0.1"
        let port = Int(environment["LOCAL_WISPR_MOONSHINE_PORT"] ?? "8179") ?? 8179
        let endpointString = environment["LOCAL_WISPR_MOONSHINE_SERVER_URL"]
            ?? environment["LOCAL_WISPR_MOONSHINE_SERVER_ENDPOINT"]
            ?? "http://\(host):\(port)/transcribe"
        guard let endpointURL = URL(string: endpointString) else { return nil }

        let endpoint = MoonshineServerEngine.normalizedTranscriptionEndpoint(endpointURL)
        guard MoonshineServerEngine.allowsEndpoint(endpoint) else { return nil }
        guard endpoint.scheme?.lowercased() == "http" else { return nil }
        guard let endpointHost = endpoint.host else { return nil }
        let endpointPort = endpoint.port ?? 80

        let pythonURL = environment["LOCAL_WISPR_MOONSHINE_PYTHON"]
            .map { URL(fileURLWithPath: $0) }
            ?? LocalWisprPaths.moonshineVirtualEnvironmentDirectory
                .appendingPathComponent("bin/python")
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else { return nil }

        guard let scriptURL = serverScriptURL(environment: environment) else { return nil }

        let backend = environment["LOCAL_WISPR_MOONSHINE_BACKEND"] ?? "voice"
        let model = environment["LOCAL_WISPR_MOONSHINE_MODEL"] ?? "UsefulSensors/moonshine-streaming-small"
        let language = environment["LOCAL_WISPR_MOONSHINE_LANGUAGE"] ?? "en"
        let voiceArch = environment["LOCAL_WISPR_MOONSHINE_VOICE_ARCH"] ?? "medium-streaming"
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWispr/moonshine-server.log")

        return MoonshineServerController(
            engine: MoonshineServerEngine(endpoint: endpoint),
            pythonURL: pythonURL,
            scriptURL: scriptURL,
            host: endpointHost,
            port: endpointPort,
            backend: backend,
            model: model,
            language: language,
            voiceArch: voiceArch,
            device: emptyToNil(environment["LOCAL_WISPR_MOONSHINE_DEVICE"]),
            torchDType: emptyToNil(environment["LOCAL_WISPR_MOONSHINE_DTYPE"]),
            maxNewTokens: emptyToNil(environment["LOCAL_WISPR_MOONSHINE_MAX_NEW_TOKENS"]),
            attentionImplementation: emptyToNil(environment["LOCAL_WISPR_MOONSHINE_ATTN_IMPLEMENTATION"]),
            shouldPreload: flag("LOCAL_WISPR_MOONSHINE_PRELOAD", in: environment, default: true),
            logURL: logURL,
            environment: environment
        )
    }

    @discardableResult
    func startIfNeeded() -> Bool {
        if MoonshineServerEngine.defaultReachabilityCheck(MoonshineServerEngine.serverRoot(for: engine.endpoint)) {
            return true
        }

        if let process {
            if process.isRunning { return true }
            self.process = nil
            try? logHandle?.close()
            logHandle = nil
        }

        do {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()

            let process = Process()
            process.executableURL = pythonURL
            process.arguments = arguments
            process.environment = processEnvironment
            process.standardOutput = handle
            process.standardError = handle

            try process.run()
            self.process = process
            self.logHandle = handle
            return true
        } catch {
            NSLog("LocalWispr failed to start managed Moonshine server: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private var arguments: [String] {
        var args = [
            scriptURL.path,
            "--host", host,
            "--port", String(port),
            "--backend", backend,
            "--model", model,
            "--language", language,
            "--voice-arch", voiceArch
        ]

        if let device {
            args += ["--device", device]
        }

        if let torchDType {
            args += ["--torch-dtype", torchDType]
        }

        if let maxNewTokens {
            args += ["--max-new-tokens", maxNewTokens]
        }

        if let attentionImplementation {
            args += ["--attn-implementation", attentionImplementation]
        }

        if !shouldPreload {
            args.append("--no-preload")
        }

        return args
    }

    private var processEnvironment: [String: String] {
        var result = environment
        result["PYTHONUNBUFFERED"] = "1"
        return result
    }

    private static func serverScriptURL(environment: [String: String]) -> URL? {
        let configured = environment["LOCAL_WISPR_MOONSHINE_SERVER_SCRIPT"]
            .map { URL(fileURLWithPath: $0) }

        let candidates = [
            configured,
            Bundle.main.resourceURL?.appendingPathComponent("moonshine_server.py"),
            LocalWisprPaths.moonshineDirectory.appendingPathComponent("moonshine_server.py")
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private static func flag(
        _ name: String,
        in environment: [String: String],
        default defaultValue: Bool = false
    ) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
