import Darwin
import Foundation
import LocalWisprCore

@main
struct LocalWisprRewriteBenchMain {
    static func main() async {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            let summary = try await RewriteBenchmark.run(
                fixtureURL: options.fixtureURL,
                iterations: options.iterations,
                warmupIterations: options.warmupIterations,
                engineMode: options.engineMode
            )

            switch options.format {
            case .metrics:
                for line in summary.metricLines {
                    print(line)
                }
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(summary)
                print(String(decoding: data, as: UTF8.self))
            case .table:
                printTable(summary)
            }

            if options.strict && (summary.totalRuns == 0 || summary.failedCases > 0 || summary.qualityScore < 1) {
                fputs("Rewrite benchmark quality gate failed: \(summary.failedCases) fixture(s) failed, quality_score=\(summary.qualityScore)\n", stderr)
                exit(2)
            }
        } catch Options.ParseError.helpRequested {
            print(Options.usage)
        } catch {
            fputs("LocalWisprRewriteBench failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printTable(_ summary: RewriteBenchmarkSummary) {
        print("Local Wispr rewrite benchmark")
        print("Engine: \(summary.engineName) [\(summary.engineMode.rawValue)]")
        print("Fixtures: \(summary.fixtureCount), iterations: \(summary.iterations), warmup: \(summary.warmupIterations)")
        print(String(format: "rewrite_ms median=%.1f p95=%.1f avg=%.1f", summary.medianRewriteMilliseconds, summary.p95RewriteMilliseconds, summary.averageRewriteMilliseconds))
        print(String(format: "quality_score=%.3f failed_cases=%d", summary.qualityScore, summary.failedCases))
        print("cleanup: llama=\(summary.llamaRuns) local=\(summary.localCleanupRuns) fallback=\(summary.fallbackRuns)")

        if !summary.failures.isEmpty {
            print("\nFailures:")
            for failure in summary.failures {
                print("- \(failure.fixtureID): \(failure.message)")
            }
        }
    }
}

private struct Options {
    enum OutputFormat: String {
        case metrics
        case json
        case table
    }

    enum ParseError: Error {
        case helpRequested
        case invalid(String)
    }

    var fixtureURL = URL(fileURLWithPath: "Tests/Fixtures/rewrite-benchmark.json")
    var iterations = 3
    var warmupIterations = 1
    var engineMode: RewriteBenchmarkEngineMode = .production
    var format: OutputFormat = .metrics
    var strict = false

    static let usage = """
    Usage: LocalWisprRewriteBench [options]

    Options:
      --fixture PATH            JSON fixture file (default: Tests/Fixtures/rewrite-benchmark.json)
      --iterations N            measured iterations per fixture (default: 3)
      --warmup N                warmup iterations per fixture (default: 1)
      --engine MODE             production | rule-based | llama-server (default: production)
      --format FORMAT           metrics | json | table (default: metrics)
      --strict                  exit nonzero if any fixture quality check fails
      -h, --help                show this help
    """

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--fixture":
                options.fixtureURL = URL(fileURLWithPath: try requiredValue(after: argument, from: &iterator))
            case "--iterations":
                options.iterations = try positiveInt(try requiredValue(after: argument, from: &iterator), label: argument)
            case "--warmup":
                options.warmupIterations = try nonnegativeInt(try requiredValue(after: argument, from: &iterator), label: argument)
            case "--engine":
                options.engineMode = try parseEngineMode(try requiredValue(after: argument, from: &iterator))
            case "--format":
                let value = try requiredValue(after: argument, from: &iterator)
                guard let format = OutputFormat(rawValue: value) else {
                    throw ParseError.invalid("unknown format: \(value)")
                }
                options.format = format
            case "--strict":
                options.strict = true
            case "-h", "--help":
                throw ParseError.helpRequested
            default:
                throw ParseError.invalid("unknown argument: \(argument)")
            }
        }

        return options
    }

    private static func requiredValue(
        after argument: String,
        from iterator: inout IndexingIterator<ArraySlice<String>>
    ) throws -> String {
        guard let value = iterator.next() else {
            throw ParseError.invalid("missing value after \(argument)")
        }
        return value
    }

    private static func positiveInt(_ value: String, label: String) throws -> Int {
        guard let intValue = Int(value), intValue > 0 else {
            throw ParseError.invalid("\(label) must be a positive integer")
        }
        return intValue
    }

    private static func nonnegativeInt(_ value: String, label: String) throws -> Int {
        guard let intValue = Int(value), intValue >= 0 else {
            throw ParseError.invalid("\(label) must be a non-negative integer")
        }
        return intValue
    }

    private static func parseEngineMode(_ value: String) throws -> RewriteBenchmarkEngineMode {
        switch value.lowercased() {
        case "production", "prod":
            return .production
        case "rule", "rules", "rule-based", "rulebased":
            return .ruleBased
        case "llama", "llama-server", "llamaserver", "server":
            return .llamaServer
        default:
            throw ParseError.invalid("unknown engine mode: \(value)")
        }
    }
}

extension Options.ParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case .invalid(let message):
            return message
        }
    }
}
