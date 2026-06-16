@testable import LocalWisprCore
import Testing

@Test
func elapsedMillisecondsReturnsNilForMissingMarks() {
    let trace = TimingTrace()
    trace.mark("start")

    #expect(trace.elapsedMilliseconds(from: "start", to: "missing") == nil)
}

@Test
func elapsedMillisecondsReturnsDurationForMarks() async throws {
    let trace = TimingTrace()
    trace.mark("start")
    try await Task.sleep(for: .milliseconds(5))
    trace.mark("end")

    let elapsed = try #require(trace.elapsedMilliseconds(from: "start", to: "end"))
    #expect(elapsed >= 1)
}

@Test
func elapsedMillisecondsUsesFirstMatchingMarks() async throws {
    let trace = TimingTrace()
    trace.mark("start")
    try await Task.sleep(for: .milliseconds(2))
    trace.mark("start")
    trace.mark("end")

    let elapsed = try #require(trace.elapsedMilliseconds(from: "start", to: "end"))
    #expect(elapsed >= 1)
}

@Test
func traceRecordsMarksInOrder() {
    let trace = TimingTrace()
    trace.mark("one")
    trace.mark("two")

    #expect(trace.marks.map(\.name) == ["one", "two"])
}
