import Foundation

enum EngineRegistry {
    static func makeSTTEngine(preferredMoonshineServer: MoonshineServerEngine? = nil) -> STTEngine {
        if let moonshine = preferredMoonshineServer ?? MoonshineServerEngine.discover() {
            return moonshine
        }

        return MissingSTTEngine(
            detail: "Run scripts/setup-local-engines.sh, then relaunch Local Wispr or start scripts/start-moonshine-server.sh"
        )
    }

    static func makeRewriteEngine() -> RewriteEngine {
        let fallback = RuleBasedRewriteEngine()

        if let llamaServer = LlamaServerRewriteEngine.discover() {
            return FallbackRewriteEngine(primary: llamaServer, fallback: fallback)
        }

        return fallback
    }

    static func statusLines() -> [String] {
        let stt: String
        if let moonshine = MoonshineServerEngine.discover() {
            stt = "STT: \(moonshine.name)"
        } else {
            stt = "STT: Moonshine not configured"
        }

        let cleanup: String
        if let llamaServer = LlamaServerRewriteEngine.discover() {
            cleanup = "Cleanup: \(llamaServer.name)"
        } else {
            cleanup = "Cleanup: Basic local rules"
        }

        return [stt, cleanup]
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
            return try await primary.startStreamingSession(startedAt: startedAt)
        }

        if let fallback = fallback as? any StreamingSTTEngine {
            return try await fallback.startStreamingSession(startedAt: startedAt)
        }

        throw LocalWisprError.missingSTTEngine("No streaming STT engine is configured")
    }
}

private struct CleanupBudgetExceeded: Error {}

struct FallbackRewriteEngine: RewriteEngine {
    let primary: RewriteEngine
    let fallback: RewriteEngine

    var name: String {
        "\(primary.name) with \(fallback.name) fallback"
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        if CleanupPrompt.shouldUseFastLocalCleanup(for: transcript.text) {
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
