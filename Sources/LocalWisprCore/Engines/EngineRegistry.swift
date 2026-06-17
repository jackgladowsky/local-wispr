import Foundation

enum EngineRegistry {
    static func makeSTTEngine(preferredWhisperServer: WhisperServerEngine? = nil) -> STTEngine {
        let server = preferredWhisperServer ?? WhisperServerEngine.discover()
        let cli = WhisperCLIEngine.discover()

        if let server, let cli {
            return FallbackSTTEngine(primary: server, fallback: cli)
        }

        if let server {
            return server
        }

        if let cli {
            return cli
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

        return fallback
    }

    static func statusLines() -> [String] {
        let stt: String
        let whisperServer = WhisperServerEngine.discover()
        let whisperCLI = WhisperCLIEngine.discover()
        if let whisperServer, let whisperCLI {
            stt = "STT: \(FallbackSTTEngine(primary: whisperServer, fallback: whisperCLI).name)"
        } else if let whisperServer {
            stt = "STT: \(whisperServer.name)"
        } else if let whisperCLI {
            stt = "STT: \(whisperCLI.name)"
        } else {
            stt = "STT: not configured"
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

struct FallbackSTTEngine: STTEngine {
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
