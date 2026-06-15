import Foundation

enum EngineRegistry {
    static func makeSTTEngine() -> STTEngine {
        if let engine = WhisperCLIEngine.discover() {
            return engine
        }

        return MissingSTTEngine(
            detail: "Install whisper-cpp and download \(LocalWisprPaths.defaultWhisperModelURL.lastPathComponent)"
        )
    }

    static func makeRewriteEngine() -> RewriteEngine {
        let fallback = RuleBasedRewriteEngine()

        if let llamaServer = LlamaServerRewriteEngine.discover() {
            return FallbackRewriteEngine(primary: llamaServer, fallback: fallback)
        }

        if let ollama = OllamaRewriteEngine.discover() {
            return FallbackRewriteEngine(primary: ollama, fallback: fallback)
        }

        if let llama = LlamaCLIRewriteEngine.discover() {
            return FallbackRewriteEngine(primary: llama, fallback: fallback)
        }

        return fallback
    }

    static func statusLines() -> [String] {
        let stt: String
        if let whisper = WhisperCLIEngine.discover() {
            stt = "STT: \(whisper.name)"
        } else {
            stt = "STT: not configured"
        }

        let cleanup: String
        if let llamaServer = LlamaServerRewriteEngine.discover() {
            cleanup = "Cleanup: \(llamaServer.name)"
        } else if let ollama = OllamaRewriteEngine.discover() {
            cleanup = "Cleanup: \(ollama.name)"
        } else if let llama = LlamaCLIRewriteEngine.discover() {
            cleanup = "Cleanup: \(llama.name)"
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
