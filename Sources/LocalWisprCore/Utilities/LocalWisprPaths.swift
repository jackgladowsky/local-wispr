import Foundation

enum LocalWisprPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalWispr", isDirectory: true)
    }

    static var moonshineDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Moonshine", isDirectory: true)
    }

    static var moonshineVirtualEnvironmentDirectory: URL {
        moonshineDirectory.appendingPathComponent("venv", isDirectory: true)
    }

    static var cleanupModelDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models/cleanup", isDirectory: true)
    }
}
