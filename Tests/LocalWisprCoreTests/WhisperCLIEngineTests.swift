@testable import LocalWisprCore
import Testing

@Test
func whisperTranscriptParserRemovesTimestampsAndJoinsLines() {
    let stdout = """
    [00:00:00.000 --> 00:00:01.000] hello there
    [00:00:01.000 --> 00:00:02.000] how are you
    """

    let cleaned = WhisperCLIEngine.cleanedTranscript(from: stdout)

    #expect(cleaned == "hello there how are you")
}

@Test
func whisperTranscriptParserDropsWhisperDiagnostics() {
    let stdout = """
    whisper_init_from_file_with_params_no_state: loading model
    system_info: n_threads = 4
    [00:00:00.000 --> 00:00:01.000] useful text
    """

    let cleaned = WhisperCLIEngine.cleanedTranscript(from: stdout)

    #expect(cleaned == "useful text")
}

@Test
func whisperTranscriptParserNormalizesWhitespace() {
    let stdout = "[00:00:00.000 --> 00:00:01.000]   hello     world   \n\n"

    let cleaned = WhisperCLIEngine.cleanedTranscript(from: stdout)

    #expect(cleaned == "hello world")
}
