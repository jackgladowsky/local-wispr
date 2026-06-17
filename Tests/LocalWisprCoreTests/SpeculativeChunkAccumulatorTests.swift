@testable import LocalWisprCore
import Testing

@Test
func speculativeAccumulatorOrdersChunksBeforeJoining() throws {
    var accumulator = SpeculativeChunkAccumulator()
    accumulator.record(
        SpeculativeTranscriptChunk(
            index: 1,
            rawText: "second chunk",
            cleanedText: "Second chunk.",
            startTime: 1,
            endTime: 2
        )
    )
    accumulator.record(
        SpeculativeTranscriptChunk(
            index: 0,
            rawText: "first chunk",
            cleanedText: "First chunk.",
            startTime: 0,
            endTime: 1
        )
    )

    let transcript = try #require(accumulator.rawTranscript())

    #expect(transcript.text == "first chunk second chunk")
    #expect(accumulator.speculativeCleanedDraft() == "First chunk. Second chunk.")
}

@Test
func speculativeAccumulatorDeduplicatesWordOverlap() {
    let joined = SpeculativeChunkAccumulator.joinDeduplicatingOverlap([
        "please send the meeting notes",
        "meeting notes to John today"
    ])

    #expect(joined == "please send the meeting notes to John today")
}

@Test
func speculativeAccumulatorFallsBackToRawTextWhenChunkCleanupIsEmpty() {
    var accumulator = SpeculativeChunkAccumulator()
    accumulator.record(
        SpeculativeTranscriptChunk(
            index: 0,
            rawText: "hello world",
            cleanedText: "  ",
            startTime: 0,
            endTime: 1
        )
    )

    #expect(accumulator.speculativeCleanedDraft() == "hello world")
}
