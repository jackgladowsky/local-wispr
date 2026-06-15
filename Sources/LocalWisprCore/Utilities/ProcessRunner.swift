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

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
            throw LocalWisprError.processTimedOut(command: executableURL.lastPathComponent)
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
