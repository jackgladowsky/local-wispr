@testable import LocalWisprCore
import Foundation
import Testing

@Test
func rewriteBenchmarkLoadsTextFixtures() throws {
    let fixtures = try RewriteBenchmark.loadFixtures(from: rewriteFixtureURL())

    #expect(fixtures.count >= 4)
    #expect(fixtures.contains { $0.id == "meeting-followup" })
    #expect(fixtures.allSatisfy { !$0.transcript.isEmpty })
}

@Test
func rewriteBenchmarkRejectsEmptyFixtureSets() async throws {
    var didThrow = false

    do {
        _ = try await RewriteBenchmark.run(
            fixtures: [],
            iterations: 1,
            warmupIterations: 0,
            engineMode: .ruleBased
        )
    } catch {
        didThrow = true
    }

    #expect(didThrow)
}

@Test
func rewriteBenchmarkRunsRuleBasedEngineAndEmitsMetrics() async throws {
    let fixture = RewriteBenchmarkFixture(
        id: "basic-note",
        transcript: "um can you send john the friday notes",
        expectedContains: ["John", "Friday", "notes"],
        forbiddenContains: ["um"]
    )

    let summary = try await RewriteBenchmark.run(
        fixtures: [fixture],
        iterations: 1,
        warmupIterations: 0,
        engineMode: .ruleBased
    )

    #expect(summary.fixtureCount == 1)
    #expect(summary.totalRuns == 1)
    #expect(summary.failedCases == 0)
    #expect(summary.qualityScore == 1)
    #expect(summary.medianRewriteMilliseconds >= 0)
    #expect(summary.localCleanupRuns == 1)
    #expect(summary.results.first?.cleanupEngineName == "Basic Local Cleanup")
    #expect(summary.metricLines.contains { $0.hasPrefix("METRIC rewrite_ms_median=") })
    #expect(summary.metricLines.contains("METRIC failed_cases=0"))
    #expect(summary.metricLines.contains("METRIC local_cleanup_runs=1"))
}

@Test
func rewriteBenchmarkExpectedSingleWordsUseWordBoundariesAndCase() async throws {
    let fixture = RewriteBenchmarkFixture(
        id: "case-sensitive-i",
        transcript: "finished",
        expectedContains: ["I"]
    )

    let summary = try await RewriteBenchmark.run(
        fixtures: [fixture],
        iterations: 1,
        warmupIterations: 0,
        engineMode: .ruleBased
    )

    #expect(summary.failedCases == 1)
    #expect(summary.qualityScore == 0)
    #expect(summary.failures.contains { $0.message.contains("missing expected text: I") })
}

private func rewriteFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/rewrite-benchmark.json")
}
