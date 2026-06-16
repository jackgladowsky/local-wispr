import Foundation

public enum RewriteBenchmarkEngineMode: String, CaseIterable, Codable, Sendable {
    case production
    case ruleBased
    case llamaServer
}

public struct RewriteBenchmarkFixture: Codable, Equatable, Sendable {
    public let id: String
    public let transcript: String
    public let expectedContains: [String]
    public let forbiddenContains: [String]
    public let notes: String?

    public init(
        id: String,
        transcript: String,
        expectedContains: [String] = [],
        forbiddenContains: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.transcript = transcript
        self.expectedContains = expectedContains
        self.forbiddenContains = forbiddenContains
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case transcript
        case expectedContains
        case forbiddenContains
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        transcript = try container.decode(String.self, forKey: .transcript)
        expectedContains = try container.decodeIfPresent([String].self, forKey: .expectedContains) ?? []
        forbiddenContains = try container.decodeIfPresent([String].self, forKey: .forbiddenContains) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct RewriteBenchmarkFailure: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let message: String

    public init(fixtureID: String, message: String) {
        self.fixtureID = fixtureID
        self.message = message
    }
}

public struct RewriteBenchmarkCaseResult: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let iteration: Int
    public let engineName: String
    public let cleanupEngineName: String
    public let output: String
    public let rewriteMilliseconds: Double
    public let passed: Bool
    public let failures: [RewriteBenchmarkFailure]

    public init(
        fixtureID: String,
        iteration: Int,
        engineName: String,
        cleanupEngineName: String,
        output: String,
        rewriteMilliseconds: Double,
        passed: Bool,
        failures: [RewriteBenchmarkFailure]
    ) {
        self.fixtureID = fixtureID
        self.iteration = iteration
        self.engineName = engineName
        self.cleanupEngineName = cleanupEngineName
        self.output = output
        self.rewriteMilliseconds = rewriteMilliseconds
        self.passed = passed
        self.failures = failures
    }
}

public struct RewriteBenchmarkSummary: Codable, Equatable, Sendable {
    public let engineMode: RewriteBenchmarkEngineMode
    public let engineName: String
    public let fixtureCount: Int
    public let iterations: Int
    public let warmupIterations: Int
    public let totalRuns: Int
    public let averageRewriteMilliseconds: Double
    public let medianRewriteMilliseconds: Double
    public let p95RewriteMilliseconds: Double
    public let qualityScore: Double
    public let failedCases: Int
    public let fallbackRuns: Int
    public let llamaRuns: Int
    public let localCleanupRuns: Int
    public let cleanupEngineCounts: [String: Int]
    public let failures: [RewriteBenchmarkFailure]
    public let results: [RewriteBenchmarkCaseResult]

    public var metricLines: [String] {
        [
            "METRIC rewrite_ms_avg=\(Self.metricValue(averageRewriteMilliseconds))",
            "METRIC rewrite_ms_median=\(Self.metricValue(medianRewriteMilliseconds))",
            "METRIC rewrite_ms_p95=\(Self.metricValue(p95RewriteMilliseconds))",
            "METRIC objective_error=\(Self.metricValue(objectiveError))",
            "METRIC quality_score=\(Self.metricValue(qualityScore))",
            "METRIC failed_cases=\(failedCases)",
            "METRIC fallback_runs=\(fallbackRuns)",
            "METRIC llama_runs=\(llamaRuns)",
            "METRIC local_cleanup_runs=\(localCleanupRuns)",
            "METRIC total_runs=\(totalRuns)",
            "METRIC fixture_count=\(fixtureCount)"
        ]
    }

    public var objectiveError: Double {
        Double(failedCases) * 1_000_000
            + (1 - qualityScore) * 100_000
            + p95RewriteMilliseconds
    }

    public init(
        engineMode: RewriteBenchmarkEngineMode,
        engineName: String,
        fixtureCount: Int,
        iterations: Int,
        warmupIterations: Int,
        totalRuns: Int,
        averageRewriteMilliseconds: Double,
        medianRewriteMilliseconds: Double,
        p95RewriteMilliseconds: Double,
        qualityScore: Double,
        failedCases: Int,
        fallbackRuns: Int,
        llamaRuns: Int,
        localCleanupRuns: Int,
        cleanupEngineCounts: [String: Int],
        failures: [RewriteBenchmarkFailure],
        results: [RewriteBenchmarkCaseResult]
    ) {
        self.engineMode = engineMode
        self.engineName = engineName
        self.fixtureCount = fixtureCount
        self.iterations = iterations
        self.warmupIterations = warmupIterations
        self.totalRuns = totalRuns
        self.averageRewriteMilliseconds = averageRewriteMilliseconds
        self.medianRewriteMilliseconds = medianRewriteMilliseconds
        self.p95RewriteMilliseconds = p95RewriteMilliseconds
        self.qualityScore = qualityScore
        self.failedCases = failedCases
        self.fallbackRuns = fallbackRuns
        self.llamaRuns = llamaRuns
        self.localCleanupRuns = localCleanupRuns
        self.cleanupEngineCounts = cleanupEngineCounts
        self.failures = failures
        self.results = results
    }

    private static func metricValue(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

public enum RewriteBenchmark {
    public static func loadFixtures(from url: URL) throws -> [RewriteBenchmarkFixture] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([RewriteBenchmarkFixture].self, from: data)
    }

    public static func run(
        fixtureURL: URL,
        iterations: Int = 3,
        warmupIterations: Int = 1,
        engineMode: RewriteBenchmarkEngineMode = .production
    ) async throws -> RewriteBenchmarkSummary {
        let fixtures = try loadFixtures(from: fixtureURL)
        return try await run(
            fixtures: fixtures,
            iterations: iterations,
            warmupIterations: warmupIterations,
            engineMode: engineMode
        )
    }

    public static func run(
        fixtures: [RewriteBenchmarkFixture],
        iterations: Int = 3,
        warmupIterations: Int = 1,
        engineMode: RewriteBenchmarkEngineMode = .production
    ) async throws -> RewriteBenchmarkSummary {
        guard !fixtures.isEmpty else {
            throw LocalWisprError.cleanupFailed("rewrite benchmark requires at least one fixture")
        }

        let measuredIterations = max(1, iterations)
        let warmups = max(0, warmupIterations)
        let engine = try makeEngine(for: engineMode)
        var results: [RewriteBenchmarkCaseResult] = []

        for fixture in fixtures {
            for iteration in 0..<(warmups + measuredIterations) {
                let isWarmup = iteration < warmups
                let measuredIteration = iteration - warmups + 1
                let result = await runCase(
                    fixture,
                    iteration: measuredIteration,
                    engine: engine
                )

                if !isWarmup {
                    results.append(result)
                }
            }
        }

        let durations = results.map(\.rewriteMilliseconds)
        let failures = results.flatMap(\.failures)
        let failedCases = Set(results.filter { !$0.passed }.map(\.fixtureID)).count
        let qualityScore = results.isEmpty ? 0 : Double(results.filter(\.passed).count) / Double(results.count)
        let cleanupCounts = Dictionary(grouping: results, by: \.cleanupEngineName).mapValues(\.count)
        let fallbackRuns = results.filter { isFallbackRun($0) }.count
        let llamaRuns = cleanupCounts
            .filter { $0.key.localizedCaseInsensitiveContains("llama.cpp server") }
            .map(\.value)
            .reduce(0, +)
        let localCleanupRuns = cleanupCounts[RuleBasedRewriteEngine().name] ?? 0

        return RewriteBenchmarkSummary(
            engineMode: engineMode,
            engineName: engine.name,
            fixtureCount: fixtures.count,
            iterations: measuredIterations,
            warmupIterations: warmups,
            totalRuns: results.count,
            averageRewriteMilliseconds: average(durations),
            medianRewriteMilliseconds: percentile(durations, 0.50),
            p95RewriteMilliseconds: percentile(durations, 0.95),
            qualityScore: qualityScore,
            failedCases: failedCases,
            fallbackRuns: fallbackRuns,
            llamaRuns: llamaRuns,
            localCleanupRuns: localCleanupRuns,
            cleanupEngineCounts: cleanupCounts,
            failures: failures,
            results: results
        )
    }

    private static func makeEngine(for mode: RewriteBenchmarkEngineMode) throws -> RewriteEngine {
        switch mode {
        case .production:
            return EngineRegistry.makeRewriteEngine()
        case .ruleBased:
            return RuleBasedRewriteEngine()
        case .llamaServer:
            return try benchmarkLlamaServerEngine()
        }
    }

    private static func benchmarkLlamaServerEngine() throws -> LlamaServerRewriteEngine {
        let environment = ProcessInfo.processInfo.environment
        let configuredURL = environment["LOCAL_WISPR_LLAMA_SERVER_URL"]
            ?? environment["LOCAL_WISPR_LLAMA_SERVER_ENDPOINT"]
            ?? "http://127.0.0.1:8080/completion"

        guard let endpoint = URL(string: configuredURL) else {
            throw LocalWisprError.cleanupFailed("Invalid llama-server URL: \(configuredURL)")
        }

        let normalizedEndpoint = normalizedCompletionEndpoint(endpoint)
        try validateLoopbackEndpoint(normalizedEndpoint, environment: environment)
        return LlamaServerRewriteEngine(endpoint: normalizedEndpoint)
    }

    private static func normalizedCompletionEndpoint(_ url: URL) -> URL {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return url.appendingPathComponent("completion")
        }

        return url
    }

    private static func validateLoopbackEndpoint(
        _ url: URL,
        environment: [String: String]
    ) throws {
        if environment["LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA"] == "1" {
            return
        }

        let host = (url.host ?? "").lowercased()
        let loopbackHosts = ["127.0.0.1", "localhost", "::1"]
        guard loopbackHosts.contains(host) else {
            throw LocalWisprError.cleanupFailed(
                "llama-server benchmark endpoint must be loopback; got \(url.absoluteString)"
            )
        }
    }

    private static func runCase(
        _ fixture: RewriteBenchmarkFixture,
        iteration: Int,
        engine: RewriteEngine
    ) async -> RewriteBenchmarkCaseResult {
        let transcript = Transcript(
            text: fixture.transcript,
            confidence: nil,
            segments: [.init(text: fixture.transcript, startTime: 0, endTime: 0)]
        )

        let started = DispatchTime.now().uptimeNanoseconds
        let output: String
        let cleanupEngineName: String
        let failures: [RewriteBenchmarkFailure]

        do {
            let cleaned = try await engine.rewrite(transcript)
            output = cleaned.text
            cleanupEngineName = cleaned.engineName ?? engine.name
            failures = evaluate(fixture, output: output)
        } catch {
            output = ""
            cleanupEngineName = "error"
            failures = [
                RewriteBenchmarkFailure(
                    fixtureID: fixture.id,
                    message: "rewrite threw: \(error.localizedDescription)"
                )
            ]
        }

        let finished = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(finished - started) / 1_000_000

        return RewriteBenchmarkCaseResult(
            fixtureID: fixture.id,
            iteration: iteration,
            engineName: engine.name,
            cleanupEngineName: cleanupEngineName,
            output: output,
            rewriteMilliseconds: elapsed,
            passed: failures.isEmpty,
            failures: failures
        )
    }

    private static func evaluate(
        _ fixture: RewriteBenchmarkFixture,
        output: String
    ) -> [RewriteBenchmarkFailure] {
        var failures: [RewriteBenchmarkFailure] = []
        let normalized = output.localizedLowercase

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append(.init(fixtureID: fixture.id, message: "output is empty"))
        }

        for expected in fixture.expectedContains {
            if !containsExpected(expected, in: output, normalizedOutput: normalized) {
                failures.append(.init(fixtureID: fixture.id, message: "missing expected text: \(expected)"))
            }
        }

        for forbidden in fixture.forbiddenContains {
            if containsForbidden(forbidden, in: normalized) {
                failures.append(.init(fixtureID: fixture.id, message: "contains forbidden text: \(forbidden)"))
            }
        }

        return failures
    }

    private static func containsExpected(
        _ expected: String,
        in output: String,
        normalizedOutput: String
    ) -> Bool {
        let requiresExactCase = expected.contains { $0.isUppercase }
        let text = requiresExactCase ? output : normalizedOutput
        let needle = requiresExactCase ? expected : expected.localizedLowercase
        let isSingleWord = needle.allSatisfy { $0.isLetter }

        if isSingleWord {
            return containsWord(needle, in: text, caseInsensitive: !requiresExactCase)
        }

        return text.contains(needle)
    }

    private static func containsForbidden(_ forbidden: String, in normalizedOutput: String) -> Bool {
        let normalizedForbidden = forbidden.localizedLowercase
        let isSingleWord = normalizedForbidden.allSatisfy { $0.isLetter }

        guard isSingleWord else {
            return normalizedOutput.contains(normalizedForbidden)
        }

        return containsWord(normalizedForbidden, in: normalizedOutput, caseInsensitive: true)
    }

    private static func containsWord(
        _ word: String,
        in text: String,
        caseInsensitive: Bool
    ) -> Bool {
        let pattern = #"(?<![\p{L}])"#
            + NSRegularExpression.escapedPattern(for: word)
            + #"(?![\p{L}])"#
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }

        return text.range(of: pattern, options: options) != nil
    }

    private static func isFallbackRun(_ result: RewriteBenchmarkCaseResult) -> Bool {
        result.engineName.localizedCaseInsensitiveContains("fallback")
            && result.cleanupEngineName == RuleBasedRewriteEngine().name
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }

        let index = Double(sorted.count - 1) * q
        let lower = Int(index.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }
}
