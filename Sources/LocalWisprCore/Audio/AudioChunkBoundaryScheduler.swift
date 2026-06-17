import Foundation

struct AdaptiveAudioChunkingConfiguration: Sendable, Equatable {
    let trailingSilenceDuration: TimeInterval
    let speechRMS: Float
    let dropsSilentChunks: Bool

    init(
        trailingSilenceDuration: TimeInterval = 0.35,
        speechRMS: Float = 0.012,
        dropsSilentChunks: Bool = false
    ) {
        self.trailingSilenceDuration = max(0, trailingSilenceDuration)
        self.speechRMS = max(0, speechRMS)
        self.dropsSilentChunks = dropsSilentChunks
    }
}

struct AudioChunkBoundaryDecision: Sendable, Equatable {
    enum Reason: Sendable, Equatable {
        case fixedDuration
        case maxDuration
        case trailingSilence
    }

    let shouldRotate: Bool
    let reason: Reason?
    let detectedSpeech: Bool?
}

struct AudioChunkBoundaryScheduler: Sendable, Equatable {
    private let adaptiveChunking: AdaptiveAudioChunkingConfiguration?
    private let chunkFrameLimit: Int64
    private let minimumFrameCount: Int64
    private let trailingSilenceFrameLimit: Int64

    private var currentFrameCount: Int64 = 0
    private var trailingSilenceFrameCount: Int64 = 0
    private var containsDetectedSpeech = false
    private var observedEnergy = false
    private var lastBufferWasSilent = false

    init(configuration: AudioChunkingConfiguration, sampleRate: Double) {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 1
        self.adaptiveChunking = configuration.adaptiveChunking
        self.chunkFrameLimit = max(1, Int64(configuration.chunkDuration * safeSampleRate))
        self.minimumFrameCount = Self.frameCount(
            for: configuration.minimumChunkDuration,
            sampleRate: safeSampleRate,
            minimum: 0
        )
        self.trailingSilenceFrameLimit = Self.frameCount(
            for: configuration.adaptiveChunking?.trailingSilenceDuration ?? 0,
            sampleRate: safeSampleRate,
            minimum: 0
        )
    }

    var detectedSpeech: Bool? {
        guard adaptiveChunking != nil, observedEnergy else { return nil }
        return containsDetectedSpeech
    }

    mutating func record(frameCount: Int64, rms: Float?) -> AudioChunkBoundaryDecision {
        let safeFrameCount = max(0, frameCount)
        currentFrameCount += safeFrameCount

        if let adaptiveChunking, let rms {
            observedEnergy = true
            if rms >= adaptiveChunking.speechRMS {
                containsDetectedSpeech = true
                trailingSilenceFrameCount = 0
                lastBufferWasSilent = false
            } else {
                trailingSilenceFrameCount += safeFrameCount
                lastBufferWasSilent = true
            }
        } else {
            lastBufferWasSilent = false
        }

        guard adaptiveChunking != nil else {
            if currentFrameCount >= chunkFrameLimit {
                return AudioChunkBoundaryDecision(
                    shouldRotate: true,
                    reason: .fixedDuration,
                    detectedSpeech: detectedSpeech
                )
            }
            return AudioChunkBoundaryDecision(
                shouldRotate: false,
                reason: nil,
                detectedSpeech: detectedSpeech
            )
        }

        if currentFrameCount >= chunkFrameLimit {
            return AudioChunkBoundaryDecision(
                shouldRotate: true,
                reason: .maxDuration,
                detectedSpeech: detectedSpeech
            )
        }

        if
            containsDetectedSpeech,
            lastBufferWasSilent,
            currentFrameCount >= minimumFrameCount,
            trailingSilenceFrameCount >= trailingSilenceFrameLimit
        {
            return AudioChunkBoundaryDecision(
                shouldRotate: true,
                reason: .trailingSilence,
                detectedSpeech: detectedSpeech
            )
        }

        return AudioChunkBoundaryDecision(
            shouldRotate: false,
            reason: nil,
            detectedSpeech: detectedSpeech
        )
    }

    mutating func reset() {
        currentFrameCount = 0
        trailingSilenceFrameCount = 0
        containsDetectedSpeech = false
        observedEnergy = false
        lastBufferWasSilent = false
    }

    private static func frameCount(for duration: TimeInterval, sampleRate: Double, minimum: Int64) -> Int64 {
        let seconds = max(0, duration)
        guard seconds > 0 else { return minimum }
        return max(minimum, Int64((seconds * sampleRate).rounded(.up)))
    }
}
