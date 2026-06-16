@testable import LocalWisprCore
import Foundation
import Testing

@Test
func audioRecordingRemovesTemporaryFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let rawURL = directory.appendingPathComponent("recording.caf")
    let wavURL = directory.appendingPathComponent("recording.wav")
    try Data("raw".utf8).write(to: rawURL)
    try Data("wav".utf8).write(to: wavURL)

    let recording = AudioRecording(
        rawURL: rawURL,
        wavURL: wavURL,
        startedAt: Date(),
        endedAt: Date()
    )

    recording.removeTemporaryFiles()

    #expect(!FileManager.default.fileExists(atPath: rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: wavURL.path))

    try? FileManager.default.removeItem(at: directory)
}
