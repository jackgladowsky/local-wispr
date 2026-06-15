import Foundation

// Cross-process paste notification consumed by the stable paste helper app.
private let pasteHelperPasteNotification = Notification.Name("dev.local-wispr.PasteHelper.paste")

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

    static func startResidentIfInstalled() async {
        guard let appURL else { return }
        await openHelper(appURL: appURL, arguments: [], wait: false)
    }

    static func paste() async -> PasteResult {
        guard appURL != nil else { return .notInstalled }

        if supportsResidentPaste {
            await startResidentIfInstalled()

            if let response = await requestResidentPaste(responseTimeout: 0.35) {
                return pasteResult(for: response)
            }
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

    private static var supportsResidentPaste: Bool {
        guard let appURL else { return false }
        let infoURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = plist["CFBundleVersion"] as? String,
            let integerVersion = Int(version)
        else {
            return false
        }

        return integerVersion >= 2
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
            await openHelper(
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
            try? await Task.sleep(for: .milliseconds(20))
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

    private static func openHelper(appURL: URL, arguments: [String], wait: Bool) async {
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
            } catch {
                return
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
