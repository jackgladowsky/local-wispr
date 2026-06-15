import Foundation

final class TimingLogger {
    let logURL: URL

    init(
        logURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWispr/mock-flow.log")
    ) {
        self.logURL = logURL
    }

    func write(_ trace: TimingTrace, insertionResult: InsertionResult) {
        let releaseToOutput = trace.elapsedMilliseconds(from: "record_stop", to: "output_final")
        let stt = trace.elapsedMilliseconds(from: "record_stop", to: "stt_final")
        let rewrite = trace.elapsedMilliseconds(from: "stt_final", to: "rewrite_final")

        writeLine(
            [
                "session=\(trace.id.uuidString)",
                "result=\(insertionResult.outcome.rawValue)",
                "detail=\"\(insertionResult.detail)\"",
                "release_to_output_ms=\(format(releaseToOutput))",
                "stt_ms=\(format(stt))",
                "rewrite_ms=\(format(rewrite))",
                "clipboard_restored=\(insertionResult.restoredClipboard)"
            ].joined(separator: " ")
        )
    }

    func write(_ trace: TimingTrace, error: Error) {
        writeLine(
            [
                "session=\(trace.id.uuidString)",
                "result=error",
                "detail=\"\(error.localizedDescription)\""
            ].joined(separator: " ")
        )
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

    private func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }
}
