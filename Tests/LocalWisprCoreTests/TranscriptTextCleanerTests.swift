@testable import LocalWisprCore
import Testing

@Test
func transcriptCleanerRemovesTimestampsAndJoinsLines() {
    let stdout = """
    [00:00:00.000 --> 00:00:01.000] hello
    [00:00:01.000 --> 00:00:02.000] world
    """

    let cleaned = TranscriptTextCleaner.cleanedTranscript(from: stdout)

    #expect(cleaned == "hello world")
}

@Test
func transcriptCleanerDropsDiagnostics() {
    let stdout = """
    system_info: runtime details
    moonshine_debug: loading model
    actual words
    """

    let cleaned = TranscriptTextCleaner.cleanedTranscript(from: stdout)

    #expect(cleaned == "actual words")
}

@Test
func transcriptCleanerNormalizesWhitespace() {
    let stdout = " hello   moonshine\n\n  text "

    let cleaned = TranscriptTextCleaner.cleanedTranscript(from: stdout)

    #expect(cleaned == "hello moonshine text")
}
