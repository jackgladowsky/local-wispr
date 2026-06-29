@testable import LocalWisprCore
import Testing

@Test
func ruleBasedCleanupRemovesCommonFillersAndCapitalizes() {
    let output = RuleBasedRewriteEngine.cleanup(
        "yeah um can you send john the notes friday"
    )

    #expect(output == "Yeah can you send John the notes Friday.")
}

@Test
func ruleBasedCleanupPreservesExistingTerminalPunctuation() {
    let output = RuleBasedRewriteEngine.cleanup("hello world?")

    #expect(output == "Hello world?")
}

@Test
func ruleBasedCleanupNormalizesWhitespaceAndPunctuationSpacing() {
    let output = RuleBasedRewriteEngine.cleanup("  hello    world   ,   friend   ")

    #expect(output == "Hello world, friend.")
}

@Test
func ruleBasedCleanupCapitalizesMultipleSentences() {
    let output = RuleBasedRewriteEngine.cleanup("hello world. how are you? fine")

    #expect(output == "Hello world. How are you? Fine.")
}

@Test
func ruleBasedCleanupCapitalizesStandaloneIAndWeekdays() {
    let output = RuleBasedRewriteEngine.cleanup("i can meet monday or thursday")

    #expect(output == "I can meet Monday or Thursday.")
}

@Test
func ruleBasedCleanupConvertsSpokenPunctuationCommands() {
    let question = RuleBasedRewriteEngine.cleanup("hello comma world question mark")
    let period = RuleBasedRewriteEngine.cleanup("hello period")

    #expect(question == "Hello, world?")
    #expect(period == "Hello.")
}

@Test
func ruleBasedCleanupConvertsDictationLineBreakCommands() {
    let output = RuleBasedRewriteEngine.cleanup("first line new line second line")

    #expect(output == "First line\nSecond line.")
}

@Test
func ruleBasedCleanupDoesNotConvertUnboundedPunctuationWords() {
    let comma = RuleBasedRewriteEngine.cleanup("the comma key is useful")
    let questionMark = RuleBasedRewriteEngine.cleanup("the question mark key is useful")
    let dash = RuleBasedRewriteEngine.cleanup("the dash character matters")

    #expect(comma == "The comma key is useful.")
    #expect(questionMark == "The question mark key is useful.")
    #expect(dash == "The dash character matters.")
}

@Test
func ruleBasedRewriteThrowsOnEmptyOutput() async {
    let engine = RuleBasedRewriteEngine()
    var caughtEmptyTranscript = false

    do {
        _ = try await engine.rewrite(
            Transcript(text: "  ", confidence: nil, segments: [])
        )
    } catch LocalWisprError.emptyTranscript {
        caughtEmptyTranscript = true
    } catch {
        caughtEmptyTranscript = false
    }

    #expect(caughtEmptyTranscript)
}
