@testable import LocalWisprCore
import Testing

@Test
func localWisprErrorDescriptionsAreActionable() {
    #expect(LocalWisprError.microphonePermissionDenied.errorDescription == "Microphone permission is required")
    #expect(LocalWisprError.recordingNotActive.errorDescription == "No active recording")
    #expect(LocalWisprError.emptyTranscript.errorDescription == "No speech was detected")
    #expect(LocalWisprError.missingSTTEngine("run Moonshine setup").errorDescription == "Local STT is not configured: run Moonshine setup")
    #expect(LocalWisprError.processTimedOut(command: "moonshine-server").errorDescription == "moonshine-server timed out")
}
