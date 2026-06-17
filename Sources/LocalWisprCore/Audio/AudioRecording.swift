import Foundation

struct AudioRecording: Sendable, Equatable {
    let rawURL: URL
    let wavURL: URL
    let startedAt: Date
    let endedAt: Date
    let chunks: [AudioChunk]
    let expectedStreamingChunkCount: Int?

    init(
        rawURL: URL,
        wavURL: URL,
        startedAt: Date,
        endedAt: Date,
        chunks: [AudioChunk] = [],
        expectedStreamingChunkCount: Int? = nil
    ) {
        self.rawURL = rawURL
        self.wavURL = wavURL
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.chunks = chunks
        self.expectedStreamingChunkCount = expectedStreamingChunkCount
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
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

    init(chunkDuration: TimeInterval = 2.5, minimumChunkDuration: TimeInterval = 0.25) {
        self.chunkDuration = max(0.5, chunkDuration)
        self.minimumChunkDuration = max(0, minimumChunkDuration)
    }
}
