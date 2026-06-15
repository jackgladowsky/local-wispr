import Foundation

struct MockSTTEngine: STTEngine {
    let name = "Mock STT"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        try await Task.sleep(for: .milliseconds(240))

        let text = "yeah so can you send john the notes from the meeting and ask if friday works um also mention that we can move it if needed"

        return Transcript(
            text: text,
            confidence: 0.98,
            segments: [
                .init(text: text, startTime: 0, endTime: 5.2)
            ]
        )
    }
}

struct MockRewriteEngine: RewriteEngine {
    let name = "Mock Cleanup"

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        try await Task.sleep(for: .milliseconds(220))

        return CleanedText(
            text: RuleBasedRewriteEngine.cleanup(transcript.text),
            engineName: name
        )
    }
}
