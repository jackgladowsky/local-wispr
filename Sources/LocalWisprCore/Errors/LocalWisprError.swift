import Foundation

enum LocalWisprError: LocalizedError, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case recordingNotActive
    case audioConversionFailed(String)
    case missingAudioRecording
    case missingSTTEngine(String)
    case processFailed(command: String, status: Int32, stderr: String)
    case processTimedOut(command: String)
    case emptyTranscript
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission is required"
        case .microphoneUnavailable:
            "Microphone input is unavailable"
        case .recordingNotActive:
            "No active recording"
        case .audioConversionFailed(let detail):
            "Audio conversion failed: \(detail)"
        case .missingAudioRecording:
            "No audio recording was provided"
        case .missingSTTEngine(let detail):
            "Local STT is not configured: \(detail)"
        case .processFailed(let command, let status, let stderr):
            "\(command) failed with status \(status): \(stderr)"
        case .processTimedOut(let command):
            "\(command) timed out"
        case .emptyTranscript:
            "No speech was detected"
        case .cleanupFailed(let detail):
            "Cleanup failed: \(detail)"
        }
    }
}
