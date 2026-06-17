import Foundation

enum AudioFileConverter {
    static func convertToWhisperReadyWav(rawURL: URL, wavURL: URL) throws {
        let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")

        guard FileManager.default.isExecutableFile(atPath: afconvert.path) else {
            throw LocalWisprError.audioConversionFailed("afconvert is unavailable")
        }

        let result = try ProcessRunner.runSync(
            executableURL: afconvert,
            arguments: [
                rawURL.path,
                wavURL.path,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1"
            ],
            timeout: 10
        )

        guard result.status == 0 else {
            throw LocalWisprError.audioConversionFailed(result.stderr)
        }
    }
}
