import Foundation

struct WhisperCLIEngine: STTEngine {
    let executableURL: URL
    let modelURL: URL

    var name: String {
        "whisper.cpp \(modelURL.deletingPathExtension().lastPathComponent)"
    }

    static func discover() -> WhisperCLIEngine? {
        let executable = ExecutableLocator.find("whisper-cli")
            ?? ExecutableLocator.find("whisper-cpp")

        let modelPath = ProcessInfo.processInfo.environment["LOCAL_WISPR_WHISPER_MODEL"]
        let modelURL = modelPath.map { URL(fileURLWithPath: $0) } ?? LocalWisprPaths.defaultWhisperModelURL

        guard
            let executable,
            FileManager.default.isReadableFile(atPath: modelURL.path)
        else {
            return nil
        }

        return WhisperCLIEngine(executableURL: executable, modelURL: modelURL)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        guard let audioURL = request.audioURL else {
            throw LocalWisprError.missingAudioRecording
        }

        let result = try await ProcessRunner.run(
            executableURL: executableURL,
            arguments: [
                "-m", modelURL.path,
                "-f", audioURL.path,
                "-nt",
                "-np"
            ],
            timeout: max(15, request.duration * 4)
        )

        guard result.status == 0 else {
            throw LocalWisprError.processFailed(
                command: executableURL.lastPathComponent,
                status: result.status,
                stderr: result.stderr
            )
        }

        let text = Self.cleanedTranscript(from: result.stdout)
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

    static func cleanedTranscript(from stdout: String) -> String {
        stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*\[[^\]]+\]\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty
                    && !trimmed.hasPrefix("whisper_")
                    && !trimmed.lowercased().contains("system_info")
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
