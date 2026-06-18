@testable import LocalWisprCore
import Foundation
import Testing

@Test
func timingLoggerWritesSuccessfulPipelineFields() throws {
    let logURL = temporaryLogURL()
    let logger = TimingLogger(logURL: logURL)
    let trace = populatedTraceForSuccess()
    let transcript = Transcript(
        text: "hello world",
        confidence: nil,
        segments: [.init(text: "hello world", startTime: 0, endTime: 1)]
    )

    logger.write(
        trace,
        insertionResult: InsertionResult(
            outcome: .pasted,
            detail: "Clipboard restored",
            restoredClipboard: true
        ),
        mode: "real",
        recording: nil,
        sttEngineName: "Moonshine server 127.0.0.1:8179",
        rewriteEngineName: "llama.cpp cleanup.gguf with Basic Local Cleanup fallback",
        transcript: transcript,
        cleaned: CleanedText(text: "Hello world.", engineName: "Basic Local Cleanup")
    )

    let contents = try String(contentsOf: logURL, encoding: .utf8)

    #expect(contents.contains("schema=pipeline-v2"))
    #expect(contents.contains("result=pasted"))
    #expect(contents.contains("detail=\"Clipboard restored\""))
    #expect(contents.contains("mode=\"real\""))
    #expect(contents.contains("cleanup_engine_used=\"Basic Local Cleanup\""))
    #expect(contents.contains("transcript_chars=11"))
    #expect(contents.contains("output_chars=12"))
    #expect(contents.contains("clipboard_restored=true"))
}

@Test
func timingLoggerEscapesQuotedFieldsAndAppends() throws {
    let logURL = temporaryLogURL()
    let logger = TimingLogger(logURL: logURL)

    let firstTrace = TimingTrace()
    firstTrace.mark("hotkey_down")
    logger.write(firstTrace, error: LocalWisprError.cleanupFailed("bad \"quote\" and \\ slash"))

    let secondTrace = TimingTrace()
    secondTrace.mark("hotkey_down")
    logger.write(secondTrace, error: LocalWisprError.emptyTranscript)

    let lines = try String(contentsOf: logURL, encoding: .utf8).split(whereSeparator: \.isNewline)

    #expect(lines.count == 2)
    #expect(lines[0].contains("result=error"))
    #expect(lines[0].contains("detail=\"Cleanup failed: bad \\\"quote\\\" and \\\\ slash\""))
    #expect(lines[0].contains("release_to_output_ms=n/a"))
    #expect(lines[1].contains("detail=\"No speech was detected\""))
}

private func populatedTraceForSuccess() -> TimingTrace {
    let trace = TimingTrace()
    for mark in [
        "hotkey_down",
        "mic_permission_start",
        "mic_permission_end",
        "audio_start_begin",
        "audio_start_end",
        "record_start",
        "target_capture_start",
        "target_capture_end",
        "record_stop",
        "audio_stop_begin",
        "audio_stop_end",
        "stt_start",
        "stt_final",
        "rewrite_start",
        "rewrite_final",
        "insert_start",
        "output_final"
    ] {
        trace.mark(mark)
    }
    return trace
}

private func temporaryLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("log")
}
