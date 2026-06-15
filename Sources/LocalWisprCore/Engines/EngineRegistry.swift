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
        if let ollama = OllamaRewriteEngine.discover() {
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

struct FallbackRewriteEngine: RewriteEngine {
    let primary: RewriteEngine
    let fallback: RewriteEngine

    var name: String {
        "\(primary.name) with \(fallback.name) fallback"
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        do {
            return try await primary.rewrite(transcript)
        } catch {
            return try await fallback.rewrite(transcript)
        }
    }
}
