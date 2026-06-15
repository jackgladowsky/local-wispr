import Foundation

struct LlamaCLIRewriteEngine: RewriteEngine {
    let executableURL: URL
    let modelURL: URL

    var name: String {
        "llama.cpp \(modelURL.deletingPathExtension().lastPathComponent)"
    }

    static func discover() -> LlamaCLIRewriteEngine? {
        let executable = ExecutableLocator.find("llama-cli")
        let modelPath = ProcessInfo.processInfo.environment["LOCAL_WISPR_CLEANUP_MODEL"]
        let modelURL = modelPath.map { URL(fileURLWithPath: $0) }
            ?? LocalWisprPaths.cleanupModelDirectory.appendingPathComponent("cleanup.gguf")

        guard
            let executable,
            FileManager.default.isReadableFile(atPath: modelURL.path)
        else {
            return nil
        }

        return LlamaCLIRewriteEngine(executableURL: executable, modelURL: modelURL)
    }

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        let result = try await ProcessRunner.run(
            executableURL: executableURL,
            arguments: [
                "-m", modelURL.path,
                "-p", CleanupPrompt.compact(for: transcript.text),
                "-n", Self.numPredict(for: transcript.text),
                "--temp", "0.1",
                "--no-display-prompt"
            ],
            timeout: 10
        )

        guard result.status == 0 else {
            throw LocalWisprError.processFailed(
                command: executableURL.lastPathComponent,
                status: result.status,
                stderr: result.stderr
            )
        }

        let cleaned = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw LocalWisprError.cleanupFailed("llama.cpp returned empty text")
        }

        return CleanedText(text: cleaned, engineName: name)
    }

    private static func numPredict(for transcript: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["LOCAL_WISPR_CLEANUP_NUM_PREDICT"].flatMap(Int.init), override > 0 {
            return String(override)
        }

        return String(min(192, max(48, transcript.count / 3 + 32)))
    }
}
