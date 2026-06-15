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
