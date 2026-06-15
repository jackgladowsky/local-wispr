import Foundation

final class TimingLogger {
    let logURL: URL

    init(
        logURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWispr/mock-flow.log")
    ) {
        self.logURL = logURL
    }

    func write(
        _ trace: TimingTrace,
        insertionResult: InsertionResult,
        mode: String,
        recording: AudioRecording?,
        sttEngineName: String,
        rewriteEngineName: String,
        transcript: Transcript,
        cleaned: CleanedText
    ) {
        var fields = commonFields(
            trace,
            result: insertionResult.outcome.rawValue,
            detail: insertionResult.detail
        )

        fields.append(contentsOf: [
            quotedField("mode", mode),
            quotedField("stt_engine", sttEngineName),
            quotedField("rewrite_engine", rewriteEngineName),
            quotedField("cleanup_engine_used", cleaned.engineName ?? rewriteEngineName),
            "recording_duration_s=\(formatSeconds(recording?.duration))",
            "transcript_chars=\(transcript.text.count)",
            "output_chars=\(cleaned.text.count)",
            "clipboard_restored=\(insertionResult.restoredClipboard)"
        ])

        writeLine(fields.joined(separator: " "))
    }

    func write(
        _ trace: TimingTrace,
        error: Error,
        mode: String? = nil,
        sttEngineName: String? = nil,
        rewriteEngineName: String? = nil
    ) {
        var fields = commonFields(
            trace,
            result: "error",
            detail: error.localizedDescription
        )

        if let mode {
            fields.append(quotedField("mode", mode))
        }

        if let sttEngineName {
            fields.append(quotedField("stt_engine", sttEngineName))
        }

        if let rewriteEngineName {
            fields.append(quotedField("rewrite_engine", rewriteEngineName))
        }

        writeLine(fields.joined(separator: " "))
    }

    private func commonFields(
        _ trace: TimingTrace,
        result: String,
        detail: String
    ) -> [String] {
        [
            "session=\(trace.id.uuidString)",
            "schema=pipeline-v2",
            "result=\(result)",
            quotedField("detail", detail),
            "total_session_ms=\(format(trace.elapsedMilliseconds(from: "hotkey_down", to: "output_final")))",
            "hotkey_to_recording_ms=\(format(trace.elapsedMilliseconds(from: "hotkey_down", to: "record_start")))",
            "mic_permission_ms=\(format(trace.elapsedMilliseconds(from: "mic_permission_start", to: "mic_permission_end")))",
            "audio_start_ms=\(format(trace.elapsedMilliseconds(from: "audio_start_begin", to: "audio_start_end")))",
            "target_capture_ms=\(format(trace.elapsedMilliseconds(from: "target_capture_start", to: "target_capture_end")))",
            "recording_ms=\(format(trace.elapsedMilliseconds(from: "record_start", to: "record_stop")))",
            "release_to_output_ms=\(format(trace.elapsedMilliseconds(from: "record_stop", to: "output_final")))",
            "audio_stop_ms=\(format(trace.elapsedMilliseconds(from: "audio_stop_begin", to: "audio_stop_end")))",
            "stt_ms=\(format(trace.elapsedMilliseconds(from: "stt_start", to: "stt_final")))",
            "rewrite_ms=\(format(trace.elapsedMilliseconds(from: "rewrite_start", to: "rewrite_final")))",
            "insert_ms=\(format(trace.elapsedMilliseconds(from: "insert_start", to: "output_final")))",
            "release_to_error_ms=\(format(trace.elapsedMilliseconds(from: "record_stop", to: "error")))"
        ]
    }

    private func writeLine(_ line: String) {
        do {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let data = "[\(timestamp)] \(line)\n".data(using: .utf8) ?? Data()

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL)
            }
        } catch {
            NSLog("LocalWispr failed to write timing log: \(error.localizedDescription)")
        }
    }

    private func quotedField(_ key: String, _ value: String) -> String {
        "\(key)=\(quote(value))"
    }

    private func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private func formatSeconds(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.3f", value)
    }
}
