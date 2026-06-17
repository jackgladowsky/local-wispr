import Foundation

// Cross-process paste notification consumed by the stable paste helper app.
private let pasteHelperPasteNotification = Notification.Name("dev.local-wispr.PasteHelper.paste")

private actor ResidentPasteHelperLaunchCache {
    private var launchedPath: String?

    func shouldLaunch(path: String) -> Bool {
        guard launchedPath != path else { return false }
        launchedPath = path
        return true
    }

    func reset(path: String) {
        guard launchedPath == path else { return }
        launchedPath = nil
    }
}

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
    private static let residentLaunchCache = ResidentPasteHelperLaunchCache()
    private static let responseFilePollInterval: Duration = .milliseconds(5)

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

    static func startResidentIfInstalled() async {
        guard let appURL, supportsResidentPaste(appURL: appURL) else { return }
        await startResident(appURL: appURL)
    }

    static func paste() async -> PasteResult {
        guard let appURL else { return .notInstalled }

        if supportsResidentPaste(appURL: appURL) {
            await startResident(appURL: appURL)

            if let response = await requestResidentPaste(responseTimeout: 0.35) {
                return pasteResult(for: response)
            }

            await residentLaunchCache.reset(path: appURL.standardizedFileURL.path)
        }

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

    private static func startResident(appURL: URL) async {
        let appPath = appURL.standardizedFileURL.path
        guard await residentLaunchCache.shouldLaunch(path: appPath) else { return }

        let launched = await openHelper(appURL: appURL, arguments: [], wait: false)
        if !launched {
            await residentLaunchCache.reset(path: appPath)
        }
    }

    private static func supportsResidentPaste(appURL: URL) -> Bool {
        let infoURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = plist["CFBundleVersion"] as? String
        else {
            return false
        }

        return bundleVersion(version, isAtLeast: "2")
    }

    private static func bundleVersion(_ version: String, isAtLeast requiredVersion: String) -> Bool {
        let current = versionComponents(version)
        let required = versionComponents(requiredVersion)
        let count = max(current.count, required.count)

        for index in 0..<count {
            let lhs = index < current.count ? current[index] : 0
            let rhs = index < required.count ? required[index] : 0

            if lhs > rhs { return true }
            if lhs < rhs { return false }
        }

        return true
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
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

    private static func requestResidentPaste(responseTimeout: TimeInterval) async -> String? {
        await withResponseFile(responseTimeout: responseTimeout) { responseURL in
            DistributedNotificationCenter.default().postNotificationName(
                pasteHelperPasteNotification,
                object: bundleIdentifier,
                userInfo: ["responseFile": responseURL.path],
                deliverImmediately: true
            )
        }
    }

    private static func runHelper(arguments: [String], responseTimeout: TimeInterval) async -> String? {
        guard let appURL else { return nil }

        return await withResponseFile(responseTimeout: responseTimeout) { responseURL in
            _ = await openHelper(
                appURL: appURL,
                arguments: arguments + ["--response-file", responseURL.path],
                wait: true
            )
        }
    }

    private static func withResponseFile(
        responseTimeout: TimeInterval,
        action: @escaping @Sendable (URL) async -> Void
    ) async -> String? {
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

        await action(responseURL)

        let deadline = Date().addingTimeInterval(responseTimeout)
        while !fileManager.fileExists(atPath: responseURL.path), Date() < deadline {
            try? await Task.sleep(for: responseFilePollInterval)
        }

        guard fileManager.fileExists(atPath: responseURL.path) else {
            return nil
        }

        do {
            let response = try String(contentsOf: responseURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? fileManager.removeItem(at: responseURL)
            return response.isEmpty ? nil : response
        } catch {
            try? fileManager.removeItem(at: responseURL)
            return nil
        }
    }

    private static func openHelper(appURL: URL, arguments: [String], wait: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", "-j"] + (wait ? ["-n", "-W"] : []) + [appURL.path]

            if !arguments.isEmpty {
                process.arguments?.append("--args")
                process.arguments?.append(contentsOf: arguments)
            }

            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                if wait {
                    process.waitUntilExit()
                }
                return true
            } catch {
                return false
            }
        }.value
    }

    private static func pasteResult(for response: String) -> PasteResult {
        switch response {
        case "pasted":
            .pasted
        case "needsPermission":
            .needsPermission
        case "secureTarget":
            .secureTarget
        default:
            .failed
        }
    }
}
