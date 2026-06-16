@testable import LocalWisprCore
import Foundation
import Testing

@Test
func fallbackRewriteUsesLocalCleanupForShortPlainTranscript() async throws {
    let engine = FallbackRewriteEngine(
        primary: FixedRewriteEngine(name: "Primary", output: "primary result"),
        fallback: FixedRewriteEngine(name: "Fallback", output: "fallback result")
    )

    let cleaned = try await engine.rewrite(transcript("hello world"))

    #expect(cleaned.text == "fallback result")
    #expect(cleaned.engineName == "Fallback")
}

@Test
func fallbackRewriteUsesPrimaryForLongTranscript() async throws {
    let engine = FallbackRewriteEngine(
        primary: FixedRewriteEngine(name: "Primary", output: "primary result"),
        fallback: FixedRewriteEngine(name: "Fallback", output: "fallback result")
    )

    let longText = String(repeating: "this should be handled by the primary cleanup engine ", count: 5)
    let cleaned = try await engine.rewrite(transcript(longText))

    #expect(cleaned.text == "primary result")
    #expect(cleaned.engineName == "Primary")
}

@Test
func fallbackRewriteUsesPrimaryForStructuredShortTranscript() async throws {
    let engine = FallbackRewriteEngine(
        primary: FixedRewriteEngine(name: "Primary", output: "primary structured result"),
        fallback: FixedRewriteEngine(name: "Fallback", output: "fallback result")
    )

    let cleaned = try await engine.rewrite(transcript("please write an email subject about lunch"))

    #expect(cleaned.text == "primary structured result")
    #expect(cleaned.engineName == "Primary")
}

@Test
func fallbackRewriteFallsBackWhenPrimaryThrows() async throws {
    let engine = FallbackRewriteEngine(
        primary: ThrowingRewriteEngine(name: "Primary"),
        fallback: FixedRewriteEngine(name: "Fallback", output: "fallback after failure")
    )

    let longText = String(repeating: "primary should try and then fail before fallback ", count: 5)
    let cleaned = try await engine.rewrite(transcript(longText))

    #expect(cleaned.text == "fallback after failure")
    #expect(cleaned.engineName == "Fallback")
}

private func transcript(_ text: String) -> Transcript {
    Transcript(
        text: text,
        confidence: nil,
        segments: [.init(text: text, startTime: 0, endTime: 1)]
    )
}

private struct FixedRewriteEngine: RewriteEngine {
    let name: String
    let output: String

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        CleanedText(text: output, engineName: name)
    }
}

private struct ThrowingRewriteEngine: RewriteEngine {
    let name: String

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        throw LocalWisprError.cleanupFailed("boom")
    }
}
