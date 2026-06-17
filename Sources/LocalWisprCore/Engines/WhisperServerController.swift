import Foundation

final class WhisperServerController {
    let engine: WhisperServerEngine

    private let executableURL: URL
    private let modelURL: URL
    private let host: String
    private let port: Int
    private let inferencePath: String
    private let logURL: URL

    private var process: Process?
    private var logHandle: FileHandle?

    init(
        engine: WhisperServerEngine,
        executableURL: URL,
        modelURL: URL,
        host: String,
        port: Int,
        inferencePath: String,
        logURL: URL
    ) {
        self.engine = engine
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.host = host
        self.port = port
        self.inferencePath = inferencePath
        self.logURL = logURL
    }

    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> WhisperServerController? {
        if flag("LOCAL_WISPR_DISABLE_WHISPER_SERVER", in: environment) {
            return nil
        }

        let requestedEngine = environment["LOCAL_WISPR_STT_ENGINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let requestedEngine, !["whisper-server", "server"].contains(requestedEngine) {
            return nil
        }

        let endpointString = environment["LOCAL_WISPR_WHISPER_SERVER_URL"]
            ?? environment["LOCAL_WISPR_WHISPER_SERVER_ENDPOINT"]
            ?? "http://127.0.0.1:8178/inference"
        guard let endpointURL = URL(string: endpointString) else { return nil }
        let endpoint = WhisperServerEngine.normalizedInferenceEndpoint(endpointURL)
        guard WhisperServerEngine.allowsEndpoint(endpoint) else { return nil }
        guard let host = endpoint.host, let port = endpoint.port else { return nil }
        let inferencePath = endpoint.path.isEmpty ? "/inference" : endpoint.path

        let modelPath = environment["LOCAL_WISPR_WHISPER_MODEL"]
        let modelURL = modelPath.map { URL(fileURLWithPath: $0) } ?? LocalWisprPaths.defaultWhisperModelURL
        guard FileManager.default.isReadableFile(atPath: modelURL.path) else { return nil }

        guard let executableURL = ExecutableLocator.find("whisper-server") else { return nil }

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWispr/whisper-server.log")

        return WhisperServerController(
            engine: WhisperServerEngine(endpoint: endpoint),
            executableURL: executableURL,
            modelURL: modelURL,
            host: host,
            port: port,
            inferencePath: inferencePath,
            logURL: logURL
        )
    }

    @discardableResult
    func startIfNeeded() -> Bool {
        if WhisperServerEngine.defaultReachabilityCheck(WhisperServerEngine.serverRoot(for: engine.endpoint)) {
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
            process.executableURL = executableURL
            process.arguments = [
                "-m", modelURL.path,
                "--host", host,
                "--port", String(port),
                "--inference-path", inferencePath,
                "-nt",
                "-sns"
            ]
            process.standardOutput = handle
            process.standardError = handle

            try process.run()
            self.process = process
            self.logHandle = handle
            return true
        } catch {
            NSLog("LocalWispr failed to start managed whisper-server: \(error.localizedDescription)")
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

    private static func flag(_ name: String, in environment: [String: String]) -> Bool {
        switch environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }
}
