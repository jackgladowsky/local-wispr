@testable import LocalWisprCore
import Foundation
import Testing

@Test
func audioRecordingResolvesReadyWavWithoutConversion() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

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

    let resolvedURL = try await recording.sttReadyWavURL { _, _ in
        throw LocalWisprError.audioConversionFailed("ready recordings should not convert")
    }

    #expect(resolvedURL == wavURL)
}

@Test
func audioRecordingConvertsDeferredWavOnDemandAndRemovesTemporaryFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let rawURL = directory.appendingPathComponent("recording.caf")
    let wavURL = directory.appendingPathComponent("recording.wav")
    try Data("raw".utf8).write(to: rawURL)

    let recording = AudioRecording(
        rawURL: rawURL,
        wavURL: wavURL,
        startedAt: Date(),
        endedAt: Date(),
        fullSessionWavAvailability: .deferred
    )

    #expect(!FileManager.default.fileExists(atPath: wavURL.path))

    let resolvedURL = try await recording.sttReadyWavURL { rawURL, wavURL in
        let rawData = try Data(contentsOf: rawURL)
        try rawData.write(to: wavURL)
    }

    #expect(resolvedURL == wavURL)
    #expect(FileManager.default.fileExists(atPath: rawURL.path))
    #expect(FileManager.default.fileExists(atPath: wavURL.path))

    recording.removeTemporaryFiles()

    #expect(!FileManager.default.fileExists(atPath: rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: wavURL.path))
}

@Test
func audioRecordingRemovesPartialDeferredWavOnConversionFailure() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let rawURL = directory.appendingPathComponent("recording.caf")
    let wavURL = directory.appendingPathComponent("recording.wav")
    try Data("raw".utf8).write(to: rawURL)

    let recording = AudioRecording(
        rawURL: rawURL,
        wavURL: wavURL,
        startedAt: Date(),
        endedAt: Date(),
        fullSessionWavAvailability: .deferred
    )

    var threwConversionFailure = false
    do {
        _ = try await recording.sttReadyWavURL { _, wavURL in
            try Data("partial".utf8).write(to: wavURL)
            throw LocalWisprError.audioConversionFailed("synthetic failure")
        }
    } catch LocalWisprError.audioConversionFailed {
        threwConversionFailure = true
    }

    #expect(threwConversionFailure)
    #expect(FileManager.default.fileExists(atPath: rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: wavURL.path))

    recording.removeTemporaryFiles()
    #expect(!FileManager.default.fileExists(atPath: rawURL.path))
}

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

@Test
func audioLevelThrottleLimitsHighFrequencyUpdates() {
    var throttle = AudioLevelThrottle(maxUpdatesPerSecond: 20)
    let start = Date()

    let first = throttle.shouldEmit(at: start)
    let second = throttle.shouldEmit(at: start.addingTimeInterval(0.02))
    let third = throttle.shouldEmit(at: start.addingTimeInterval(0.051))

    #expect(first)
    #expect(!second)
    #expect(third)
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
