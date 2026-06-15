import Foundation

enum LocalWisprPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalWispr", isDirectory: true)
    }

    static var whisperModelDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models/whisper", isDirectory: true)
    }

    static var cleanupModelDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models/cleanup", isDirectory: true)
    }

    static var defaultWhisperModelURL: URL {
        whisperModelDirectory.appendingPathComponent("ggml-base.en.bin")
    }
}
