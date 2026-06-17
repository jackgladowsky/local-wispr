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
    let chunkRawURL = directory.appendingPathComponent("recording-chunk-0.caf")
    let chunkWavURL = directory.appendingPathComponent("recording-chunk-0.wav")
    try Data("raw".utf8).write(to: rawURL)
    try Data("wav".utf8).write(to: wavURL)
    try Data("chunk raw".utf8).write(to: chunkRawURL)
    try Data("chunk wav".utf8).write(to: chunkWavURL)

    let recording = AudioRecording(
        rawURL: rawURL,
        wavURL: wavURL,
        startedAt: Date(),
        endedAt: Date(),
        chunks: [
            AudioChunk(
                index: 0,
                rawURL: chunkRawURL,
                wavURL: chunkWavURL,
                startedAt: Date(),
                endedAt: Date()
            )
        ],
        expectedStreamingChunkCount: 1
    )

    recording.removeTemporaryFiles()

    #expect(!FileManager.default.fileExists(atPath: rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: wavURL.path))
    #expect(!FileManager.default.fileExists(atPath: chunkRawURL.path))
    #expect(!FileManager.default.fileExists(atPath: chunkWavURL.path))

    try? FileManager.default.removeItem(at: directory)
}
