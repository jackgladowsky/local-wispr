@testable import LocalWisprCore
import Foundation
import Testing

@Test
func processRunnerCapturesStdoutAndExitStatus() throws {
    let result = try ProcessRunner.runSync(
        executableURL: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["hello"],
        timeout: 2
    )

    #expect(result.status == 0)
    #expect(result.stdout == "hello\n")
    #expect(result.stderr == "")
}

@Test
func processRunnerReturnsNonzeroStatusAndStderr() throws {
    let result = try ProcessRunner.runSync(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo problem >&2; exit 7"],
        timeout: 2
    )

    #expect(result.status == 7)
    #expect(result.stdout == "")
    #expect(result.stderr == "problem\n")
}

@Test
func processRunnerAsyncPathUsesSyncImplementation() async throws {
    let result = try await ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["async"],
        timeout: 2
    )

    #expect(result == ProcessResult(status: 0, stdout: "async\n", stderr: ""))
}
