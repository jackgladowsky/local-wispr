@testable import LocalWisprCore
import Testing

@Test
func localWisprErrorDescriptionsAreActionable() {
    #expect(LocalWisprError.microphonePermissionDenied.errorDescription == "Microphone permission is required")
    #expect(LocalWisprError.recordingNotActive.errorDescription == "No active recording")
    #expect(LocalWisprError.emptyTranscript.errorDescription == "No speech was detected")
    #expect(LocalWisprError.missingSTTEngine("install whisper").errorDescription == "Local STT is not configured: install whisper")
    #expect(LocalWisprError.processTimedOut(command: "whisper-cli").errorDescription == "whisper-cli timed out")
}
