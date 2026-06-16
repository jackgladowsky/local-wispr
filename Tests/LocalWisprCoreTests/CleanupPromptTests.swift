@testable import LocalWisprCore
import Testing

@Test
func fastCleanupAllowsShortPlainTranscript() {
    #expect(CleanupPrompt.shouldUseFastLocalCleanup(for: "send the notes Friday"))
}

@Test
func fastCleanupAllowsEmptyTranscriptToReachLocalEmptyHandling() {
    #expect(CleanupPrompt.shouldUseFastLocalCleanup(for: "   \n  "))
}

@Test
func fastCleanupRejectsStructuredShortTranscript() {
    #expect(!CleanupPrompt.shouldUseFastLocalCleanup(for: "email subject follow up"))
    #expect(!CleanupPrompt.shouldUseFastLocalCleanup(for: "Subject: follow up"))
    #expect(!CleanupPrompt.shouldUseFastLocalCleanup(for: "draft an email"))
    #expect(!CleanupPrompt.shouldUseFastLocalCleanup(for: "first line\nsecond line"))
}

@Test
func fastCleanupRejectsLongTranscript() {
    let transcript = String(repeating: "this is a longer dictated phrase ", count: 8)

    #expect(!CleanupPrompt.shouldUseFastLocalCleanup(for: transcript))
}

@Test
func compactPromptIncludesInstructionsAndTranscript() {
    let prompt = CleanupPrompt.compact(for: "um hello world")

    #expect(prompt.contains("Fix capitalization and punctuation"))
    #expect(prompt.contains("Preserve wording"))
    #expect(prompt.contains("Remove filler words exactly like um, uh, erm, and ah"))
    #expect(prompt.contains("Transcript:\num hello world"))
}
