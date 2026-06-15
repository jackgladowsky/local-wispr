import Foundation

enum PasteHelperController {
    enum Status: Equatable {
        case checking
        case notInstalled
        case needsPermission
        case trusted
        case unavailable

        var title: String {
            switch self {
            case .checking:
                "Checking"
            case .notInstalled:
                "Not Installed"
            case .needsPermission:
                "Needs Permission"
            case .trusted:
                "Allowed"
            case .unavailable:
                "Unavailable"
            }
        }

        var isTrusted: Bool {
            self == .trusted
        }
    }

    enum PasteResult: Equatable {
        case pasted
        case notInstalled
        case needsPermission
        case secureTarget
        case failed
    }

    static let bundleIdentifier = "dev.local-wispr.PasteHelper"
    private static let appName = "Local Wispr Paste Helper.app"

    static var appURL: URL? {
        candidateAppURLs.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var isInstalled: Bool {
        appURL != nil
    }

    static func checkStatus() async -> Status {
        guard appURL != nil else { return .notInstalled }

        switch await runHelper(arguments: ["--check"], responseTimeout: 1.5) {
        case "trusted":
            return .trusted
        case "needsPermission":
            return .needsPermission
        default:
            return .unavailable
        }
    }

    static func requestTrustPrompt() async {
        _ = await runHelper(arguments: ["--request-permission"], responseTimeout: 3.0)
    }

    static func paste() async -> PasteResult {
        guard appURL != nil else { return .notInstalled }

        switch await runHelper(arguments: ["--paste"], responseTimeout: 1.5) {
        case "pasted":
            return .pasted
        case "needsPermission":
            return .needsPermission
        case "secureTarget":
            return .secureTarget
        default:
            return .failed
        }
    }

    private static var candidateAppURLs: [URL] {
        let fileManager = FileManager.default
        let installed = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent(appName)
        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(appName)
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent(appName)

        return uniqueURLs([installed, sibling, bundled])
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func runHelper(arguments: [String], responseTimeout: TimeInterval) async -> String? {
        guard let appURL else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let responseDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("LocalWisprPasteHelper", isDirectory: true)

            do {
                try fileManager.createDirectory(
                    at: responseDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }

            let responseURL = responseDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("txt")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [
                "-g",
                "-j",
                "-n",
                "-W",
                appURL.path,
                "--args"
            ] + arguments + ["--response-file", responseURL.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let deadline = Date().addingTimeInterval(responseTimeout)
                while !fileManager.fileExists(atPath: responseURL.path), Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }

                guard fileManager.fileExists(atPath: responseURL.path) else {
                    return nil
                }

                let response = try String(contentsOf: responseURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try? fileManager.removeItem(at: responseURL)
                return response.isEmpty ? nil : response
            } catch {
                try? fileManager.removeItem(at: responseURL)
                return nil
            }
        }.value
    }
}
