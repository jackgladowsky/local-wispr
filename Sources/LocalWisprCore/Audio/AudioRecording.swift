import Foundation

struct AudioRecording: Sendable, Equatable {
    enum FullSessionWavAvailability: Sendable, Equatable {
        case ready
        case deferred
    }

    let rawURL: URL
    let wavURL: URL
    let startedAt: Date
    let endedAt: Date
    let chunks: [AudioChunk]
    let expectedStreamingChunkCount: Int?
    let fullSessionWavAvailability: FullSessionWavAvailability

    init(
        rawURL: URL,
        wavURL: URL,
        startedAt: Date,
        endedAt: Date,
        chunks: [AudioChunk] = [],
        expectedStreamingChunkCount: Int? = nil,
        fullSessionWavAvailability: FullSessionWavAvailability = .ready
    ) {
        self.rawURL = rawURL
        self.wavURL = wavURL
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.chunks = chunks
        self.expectedStreamingChunkCount = expectedStreamingChunkCount
        self.fullSessionWavAvailability = fullSessionWavAvailability
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    func whisperReadyWavURL(
        converter: @escaping @Sendable (_ rawURL: URL, _ wavURL: URL) throws -> Void = AudioFileConverter.convertToWhisperReadyWav
    ) async throws -> URL {
        switch fullSessionWavAvailability {
        case .ready:
            return wavURL
        case .deferred:
            let rawURL = rawURL
            let wavURL = wavURL
            guard !FileManager.default.fileExists(atPath: wavURL.path) else {
                return wavURL
            }

            do {
                try await Task.detached(priority: .utility) {
                    try converter(rawURL, wavURL)
                }.value
                return wavURL
            } catch {
                try? FileManager.default.removeItem(at: wavURL)
                throw error
            }
        }
    }

    func removeTemporaryFiles(fileManager: FileManager = .default) {
        for url in [rawURL, wavURL] {
            try? fileManager.removeItem(at: url)
        }

        for chunk in chunks {
            chunk.removeTemporaryFiles(fileManager: fileManager)
        }
    }
}

struct AudioChunk: Sendable, Equatable {
    let index: Int
    let rawURL: URL
    let wavURL: URL
    let startedAt: Date
    let endedAt: Date
    let shouldTranscribe: Bool
    let detectedSpeech: Bool?

    init(
        index: Int,
        rawURL: URL,
        wavURL: URL,
        startedAt: Date,
        endedAt: Date,
        shouldTranscribe: Bool = true,
        detectedSpeech: Bool? = nil
    ) {
        self.index = index
        self.rawURL = rawURL
        self.wavURL = wavURL
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.shouldTranscribe = shouldTranscribe
        self.detectedSpeech = detectedSpeech
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    func removeTemporaryFiles(fileManager: FileManager = .default) {
        for url in [rawURL, wavURL] {
            try? fileManager.removeItem(at: url)
        }
    }
}

struct AudioChunkingConfiguration: Sendable, Equatable {
    let chunkDuration: TimeInterval
    let minimumChunkDuration: TimeInterval
    let adaptiveChunking: AdaptiveAudioChunkingConfiguration?

    init(
        chunkDuration: TimeInterval = 2.5,
        minimumChunkDuration: TimeInterval = 0.25,
        adaptiveChunking: AdaptiveAudioChunkingConfiguration? = nil
    ) {
        self.chunkDuration = max(0.5, chunkDuration)
        self.minimumChunkDuration = max(0, minimumChunkDuration)
        self.adaptiveChunking = adaptiveChunking
    }
}
