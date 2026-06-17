@testable import LocalWisprCore
import Testing

@Test
func fixedChunkBoundarySchedulerRotatesAtConfiguredDuration() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(chunkDuration: 1.0, minimumChunkDuration: 0.25),
        sampleRate: 100
    )

    #expect(!scheduler.record(frameCount: 99, rms: nil).shouldRotate)

    let decision = scheduler.record(frameCount: 1, rms: nil)
    #expect(decision.shouldRotate)
    #expect(decision.reason == .fixedDuration)
    #expect(decision.detectedSpeech == nil)
}

@Test
func adaptiveChunkBoundaryRotatesAfterSpeechAndTrailingSilence() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(
            chunkDuration: 2.0,
            minimumChunkDuration: 0.5,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(
                trailingSilenceDuration: 0.2,
                speechRMS: 0.05
            )
        ),
        sampleRate: 100
    )

    #expect(!scheduler.record(frameCount: 20, rms: 0.10).shouldRotate)
    #expect(!scheduler.record(frameCount: 20, rms: 0.00).shouldRotate)

    let decision = scheduler.record(frameCount: 10, rms: 0.00)
    #expect(decision.shouldRotate)
    #expect(decision.reason == .trailingSilence)
    #expect(decision.detectedSpeech == true)
}

@Test
func adaptiveChunkBoundaryDoesNotRotateOnSilenceBeforeMinimumDuration() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(
            chunkDuration: 2.0,
            minimumChunkDuration: 1.0,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(
                trailingSilenceDuration: 0.2,
                speechRMS: 0.05
            )
        ),
        sampleRate: 100
    )

    #expect(!scheduler.record(frameCount: 10, rms: 0.10).shouldRotate)
    #expect(!scheduler.record(frameCount: 20, rms: 0.00).shouldRotate)
}

@Test
func adaptiveChunkBoundaryUsesMaxDurationForContinuousSpeech() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(
            chunkDuration: 0.5,
            minimumChunkDuration: 0.1,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(
                trailingSilenceDuration: 0.1,
                speechRMS: 0.05
            )
        ),
        sampleRate: 100
    )

    #expect(!scheduler.record(frameCount: 49, rms: 0.10).shouldRotate)

    let decision = scheduler.record(frameCount: 1, rms: 0.10)
    #expect(decision.shouldRotate)
    #expect(decision.reason == .maxDuration)
    #expect(decision.detectedSpeech == true)
}

@Test
func adaptiveChunkBoundaryReportsSilentChunksAtMaxDuration() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(
            chunkDuration: 0.5,
            minimumChunkDuration: 0.1,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(
                trailingSilenceDuration: 0.1,
                speechRMS: 0.05
            )
        ),
        sampleRate: 100
    )

    let decision = scheduler.record(frameCount: 50, rms: 0.0)
    #expect(decision.shouldRotate)
    #expect(decision.reason == .maxDuration)
    #expect(decision.detectedSpeech == false)
}

@Test
func adaptiveChunkBoundaryDoesNotMarkSpeechWhenEnergyIsUnavailable() {
    var scheduler = AudioChunkBoundaryScheduler(
        configuration: AudioChunkingConfiguration(
            chunkDuration: 0.5,
            minimumChunkDuration: 0.1,
            adaptiveChunking: AdaptiveAudioChunkingConfiguration(
                trailingSilenceDuration: 0.1,
                speechRMS: 0.05
            )
        ),
        sampleRate: 100
    )

    let decision = scheduler.record(frameCount: 50, rms: nil)
    #expect(decision.shouldRotate)
    #expect(decision.reason == .maxDuration)
    #expect(decision.detectedSpeech == nil)
}
