@testable import LocalWisprCore
import Foundation
import Testing

@Test
func speculativeCoordinatorProcessesChunkAndRemovesTemporaryFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let chunk = try makeChunk(in: directory, index: 0, text: "hello")
    let coordinator = SpeculativeDictationCoordinator(
        sttEngine: StubSTTEngine(),
        rewriteEngine: StubRewriteEngine(),
        startedAt: chunk.startedAt,
        configuration: SpeculativeDictationConfiguration(
            chunkDuration: 1,
            minimumChunkDuration: 0.01,
            chunkArrivalGrace: 0.01
        )
    )

    await coordinator.accept(chunk)
    let draft = try await coordinator.finish(finalChunks: [], expectedChunkCount: 1)

    #expect(draft.transcript.text == "hello")
    #expect(draft.speculativeCleanedText == "HELLO")
    #expect(!FileManager.default.fileExists(atPath: chunk.rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: chunk.wavURL.path))
}

@Test
func speculativeCoordinatorSkipsTinyChunksAndRemovesTemporaryFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let chunk = try makeChunk(in: directory, index: 0, text: "tiny", duration: 0.01)
    let coordinator = SpeculativeDictationCoordinator(
        sttEngine: StubSTTEngine(),
        rewriteEngine: StubRewriteEngine(),
        startedAt: chunk.startedAt,
        configuration: SpeculativeDictationConfiguration(
            chunkDuration: 1,
            minimumChunkDuration: 0.5,
            chunkArrivalGrace: 0.01
        )
    )

    await coordinator.accept(chunk)

    var threwEmptyTranscript = false
    do {
        _ = try await coordinator.finish(finalChunks: [], expectedChunkCount: 1)
    } catch LocalWisprError.emptyTranscript {
        threwEmptyTranscript = true
    }

    #expect(threwEmptyTranscript)
    #expect(!FileManager.default.fileExists(atPath: chunk.rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: chunk.wavURL.path))
}

@Test
func speculativeCoordinatorSkipsNonTranscribableChunksAndRemovesTemporaryFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let chunk = try makeChunk(
        in: directory,
        index: 0,
        text: "silent",
        shouldTranscribe: false,
        detectedSpeech: false
    )
    let coordinator = SpeculativeDictationCoordinator(
        sttEngine: StubSTTEngine(),
        rewriteEngine: StubRewriteEngine(),
        startedAt: chunk.startedAt,
        configuration: SpeculativeDictationConfiguration(
            chunkDuration: 1,
            minimumChunkDuration: 0.01,
            chunkArrivalGrace: 0.01,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(dropsSilentChunks: true)
        )
    )

    await coordinator.accept(chunk)

    var threwEmptyTranscript = false
    do {
        _ = try await coordinator.finish(finalChunks: [], expectedChunkCount: 1)
    } catch LocalWisprError.emptyTranscript {
        threwEmptyTranscript = true
    }

    #expect(threwEmptyTranscript)
    #expect(!FileManager.default.fileExists(atPath: chunk.rawURL.path))
    #expect(!FileManager.default.fileExists(atPath: chunk.wavURL.path))
}

@Test
func speculativeCoordinatorIgnoresRewriteEmptyTranscriptChunks() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let fillerChunk = try makeChunk(in: directory, index: 0, text: "um")
    let wordsChunk = try makeChunk(in: directory, index: 1, text: "hello")
    let coordinator = SpeculativeDictationCoordinator(
        sttEngine: StubSTTEngine(),
        rewriteEngine: EmptyForFillerRewriteEngine(),
        startedAt: fillerChunk.startedAt,
        configuration: SpeculativeDictationConfiguration(
            chunkDuration: 1,
            minimumChunkDuration: 0.01,
            chunkArrivalGrace: 0.01
        )
    )

    await coordinator.accept(fillerChunk)
    await coordinator.accept(wordsChunk)
    let draft = try await coordinator.finish(finalChunks: [], expectedChunkCount: 2)

    #expect(draft.transcript.text == "hello")
    #expect(draft.speculativeCleanedText == "HELLO")
}

private struct StubSTTEngine: STTEngine {
    let name = "Stub STT"

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let text = request.audioURL?.deletingPathExtension().lastPathComponent.components(separatedBy: "-").last ?? "chunk"
        return Transcript(
            text: text,
            confidence: nil,
            segments: [TranscriptSegment(text: text, startTime: 0, endTime: request.duration)]
        )
    }
}

private struct StubRewriteEngine: RewriteEngine {
    let name = "Stub Rewrite"

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        CleanedText(text: transcript.text.uppercased(), engineName: name)
    }
}

private struct EmptyForFillerRewriteEngine: RewriteEngine {
    let name = "Empty For Filler"

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        if transcript.text == "um" {
            throw LocalWisprError.emptyTranscript
        }
        return CleanedText(text: transcript.text.uppercased(), engineName: name)
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeChunk(
    in directory: URL,
    index: Int,
    text: String,
    duration: TimeInterval = 1,
    shouldTranscribe: Bool = true,
    detectedSpeech: Bool? = nil
) throws -> AudioChunk {
    let rawURL = directory.appendingPathComponent("chunk-\(index)-\(text).caf")
    let wavURL = directory.appendingPathComponent("chunk-\(index)-\(text).wav")
    try Data("raw".utf8).write(to: rawURL)
    try Data("wav".utf8).write(to: wavURL)
    let startedAt = Date()
    return AudioChunk(
        index: index,
        rawURL: rawURL,
        wavURL: wavURL,
        startedAt: startedAt,
        endedAt: startedAt.addingTimeInterval(duration),
        shouldTranscribe: shouldTranscribe,
        detectedSpeech: detectedSpeech
    )
}
