import Foundation

enum EngineRegistry {
    static func makeSTTEngine(
        preferredMoonshineServer: MoonshineServerEngine? = nil,
        managedMoonshineServerController: MoonshineServerController? = nil
    ) -> STTEngine {
        let discoveredMoonshineServer = managedMoonshineServerController == nil
            ? MoonshineServerEngine.discover()
            : nil
        return makeSTTEngine(
            preferredMoonshineNative: MoonshineNativeEngine.discover(),
            preferredMoonshineServer: preferredMoonshineServer ?? discoveredMoonshineServer,
            managedMoonshineServerController: managedMoonshineServerController
        )
    }

    static func makeSTTEngine(
        preferredMoonshineNative: MoonshineNativeEngine?,
        preferredMoonshineServer: MoonshineServerEngine?,
        managedMoonshineServerController: MoonshineServerController? = nil
    ) -> STTEngine {
        let serverFallback: STTEngine? = preferredMoonshineServer
            ?? managedMoonshineServerController.map { ManagedMoonshineServerFallbackEngine(controller: $0) }

        if let native = preferredMoonshineNative {
            native.preload()
            if let serverFallback {
                return FallbackSTTEngine(primary: native, fallback: serverFallback)
            }
            return native
        }

        if let serverFallback {
            return serverFallback
        }

        return MissingSTTEngine(
            detail: "Run scripts/setup-local-engines.sh, then relaunch Local Wispr"
        )
    }

    static func makeRewriteEngine() -> RewriteEngine {
        let fallback = RuleBasedRewriteEngine()

        if let openAICompatible = OpenAICompatibleRewriteEngine.discover() {
            return FallbackRewriteEngine(
                primary: openAICompatible,
                fallback: fallback,
                usesFastLocalShortCircuit: shouldShortCircuitSmartCleanup()
            )
        }

        if let llamaServer = LlamaServerRewriteEngine.discover() {
            return FallbackRewriteEngine(primary: llamaServer, fallback: fallback)
        }

        return fallback
    }

    static func statusLines() -> [String] {
        let stt: String
        if let nativeMoonshine = MoonshineNativeEngine.discover() {
            stt = "STT: \(nativeMoonshine.name)"
        } else if let moonshine = MoonshineServerEngine.discover() {
            stt = "STT: \(moonshine.name)"
        } else {
            stt = "STT: Moonshine not configured"
        }

        let cleanup: String
        if let openAICompatible = OpenAICompatibleRewriteEngine.discover() {
            cleanup = "Cleanup: \(openAICompatible.name)"
        } else if let llamaServer = LlamaServerRewriteEngine.discover() {
            cleanup = "Cleanup: \(llamaServer.name)"
        } else {
            cleanup = "Cleanup: Basic local rules"
        }

        return [stt, cleanup]
    }

    private static func shouldShortCircuitSmartCleanup() -> Bool {
        ProcessInfo.processInfo.environment["LOCAL_WISPR_SMART_CLEANUP_SHORT_CIRCUIT"] == "1"
    }
}

struct MissingSTTEngine: STTEngine {
    let name = "Missing Local STT"
    let detail: String

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        throw LocalWisprError.missingSTTEngine(detail)
    }
}

struct FallbackSTTEngine: StreamingSTTEngine {
    let primary: STTEngine
    let fallback: STTEngine

    var name: String {
        "\(primary.name) with \(fallback.name) fallback"
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        do {
            return try await primary.transcribe(request)
        } catch {
            NSLog("LocalWispr STT primary failed; falling back: \(error.localizedDescription)")
            return try await fallback.transcribe(request)
        }
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        if let primary = primary as? any StreamingSTTEngine {
            do {
                return try await primary.startStreamingSession(startedAt: startedAt)
            } catch {
                if let fallback = fallback as? any StreamingSTTEngine {
                    NSLog("LocalWispr streaming STT primary failed to start; falling back: \(error.localizedDescription)")
                    return try await fallback.startStreamingSession(startedAt: startedAt)
                }
                throw error
            }
        }

        if let fallback = fallback as? any StreamingSTTEngine {
            return try await fallback.startStreamingSession(startedAt: startedAt)
        }

        throw LocalWisprError.missingSTTEngine("No streaming STT engine is configured")
    }
}

final class ManagedMoonshineServerFallbackEngine: StreamingSTTEngine, @unchecked Sendable {
    private let controller: MoonshineServerController
    private let lock = NSLock()

    init(controller: MoonshineServerController) {
        self.controller = controller
    }

    var name: String {
        "Managed \(controller.engine.name)"
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        try await engine().transcribe(request)
    }

    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession {
        try await engine().startStreamingSession(startedAt: startedAt)
    }

    private func engine() async throws -> MoonshineServerEngine {
        let started = lock.withLock {
            controller.startIfNeeded()
        }
        guard started else {
            throw LocalWisprError.missingSTTEngine("Moonshine server fallback could not be started")
        }

        let engine = controller.engine
        let root = MoonshineServerEngine.serverRoot(for: engine.endpoint)
        let timeout = ProcessInfo.processInfo.environment["LOCAL_WISPR_MOONSHINE_SERVER_READY_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init)
            .map { max(0.1, $0) }
            ?? 10
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if MoonshineServerEngine.defaultReachabilityCheck(root) {
                return engine
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw LocalWisprError.missingSTTEngine("Moonshine server fallback did not become ready at \(root.absoluteString)")
    }
}

private struct CleanupBudgetExceeded: Error {}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

struct FallbackRewriteEngine: RewriteEngine {
    let primary: RewriteEngine
    let fallback: RewriteEngine
    var usesFastLocalShortCircuit = true

    var name: String {
        "\(primary.name) with \(fallback.name) fallback"
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        if usesFastLocalShortCircuit, CleanupPrompt.shouldUseFastLocalCleanup(for: transcript.text) {
            return try await fallback.rewrite(transcript)
        }

        do {
            if primary is LlamaCLIRewriteEngine {
                // The CLI path launches a subprocess that is not safely cancellable mid-run.
                // Prefer llama-server for latency-budgeted llama.cpp cleanup.
                return try await primary.rewrite(transcript)
            }

            return try await rewriteWithBudget(transcript)
        } catch {
            return try await fallback.rewrite(transcript)
        }
    }

    private func rewriteWithBudget(_ transcript: Transcript) async throws -> CleanedText {
        let budget = Int(ProcessInfo.processInfo.environment["LOCAL_WISPR_LLM_CLEANUP_BUDGET_MS"] ?? "650") ?? 650
        guard budget > 0 else {
            return try await primary.rewrite(transcript)
        }

        return try await withThrowingTaskGroup(of: CleanedText.self) { group in
            group.addTask {
                try await primary.rewrite(transcript)
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(budget))
                throw CleanupBudgetExceeded()
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw CleanupBudgetExceeded()
            }

            return result
        }
    }
}
