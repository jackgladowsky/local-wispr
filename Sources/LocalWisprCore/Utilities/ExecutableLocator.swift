import Foundation

enum ExecutableLocator {
    static func find(_ executableName: String) -> URL? {
        let candidates = absoluteCandidates(for: executableName)

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private static func absoluteCandidates(for executableName: String) -> [URL] {
        var paths = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
            "/usr/bin/\(executableName)",
            "/bin/\(executableName)"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { "\($0)/\(executableName)" }
            )
        }

        return Array(Set(paths)).map { URL(fileURLWithPath: $0) }
    }
}
