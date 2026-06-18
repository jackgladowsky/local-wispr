import Foundation

enum DictationSource: String, Sendable {
    case mock
    case microphone
    case fixture
}

struct TranscriptionRequest: Sendable {
    let startedAt: Date
    let endedAt: Date
    let source: DictationSource
    let audioURL: URL?
    let duration: TimeInterval
}

struct StreamingAudioBuffer: Sendable, Equatable {
    let samples: [Float]
    let sampleRate: Double
    let receivedAt: Date

    var duration: TimeInterval {
        guard sampleRate.isFinite, sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

struct TranscriptSegment: Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct Transcript: Equatable, Sendable {
    let text: String
    let confidence: Double?
    let segments: [TranscriptSegment]
}

struct CleanedText: Equatable, Sendable {
    let text: String
    let engineName: String?

    init(text: String, engineName: String? = nil) {
        self.text = text
        self.engineName = engineName
    }
}

protocol STTEngine: Sendable {
    var name: String { get }
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}

protocol StreamingSTTEngine: STTEngine {
    func startStreamingSession(startedAt: Date) async throws -> StreamingSTTSession
}

protocol StreamingSTTSession: Sendable {
    var name: String { get }
    func append(_ buffer: StreamingAudioBuffer) async throws
    func finish(endedAt: Date) async throws -> Transcript
    func cancel() async
}

protocol RewriteEngine: Sendable {
    var name: String { get }
    func rewrite(_ transcript: Transcript) async throws -> CleanedText
}
