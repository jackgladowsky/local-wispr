import Foundation

struct ProcessResult: Sendable, Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            try runSync(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout
            )
        }.value
    }

    static func runSync(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw LocalWisprError.processTimedOut(command: executableURL.lastPathComponent)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }
}
