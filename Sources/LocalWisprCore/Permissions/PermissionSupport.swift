import AVFoundation
import AppKit

enum PermissionSupport {
    enum StatusKind: Equatable {
        case allowed
        case actionRequired
        case notRequested
        case restricted
        case unknown

        var title: String {
            switch self {
            case .allowed:
                "Allowed"
            case .actionRequired:
                "Action Required"
            case .notRequested:
                "Not Requested"
            case .restricted:
                "Restricted"
            case .unknown:
                "Unknown"
            }
        }

        var isAllowed: Bool {
            self == .allowed
        }
    }

    struct Snapshot: Equatable {
        let accessibility: StatusKind
        let microphone: StatusKind

        var isComplete: Bool {
            accessibility.isAllowed && microphone.isAllowed
        }
    }

    @MainActor
    static var snapshot: Snapshot {
        Snapshot(
            accessibility: InsertionController.isAccessibilityTrusted ? .allowed : .actionRequired,
            microphone: microphoneStatus
        )
    }

    static var microphoneStatusText: String {
        microphoneStatus.title
    }

    static var microphoneStatus: StatusKind {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .allowed
        case .notDetermined:
            .notRequested
        case .denied:
            .actionRequired
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }

    @MainActor
    static var accessibilityStatusText: String {
        InsertionController.isAccessibilityTrusted ? "Allowed" : "Not allowed"
    }

    @MainActor
    static var needsOnboarding: Bool {
        let current = snapshot

        if current.isComplete {
            PermissionMemory.rememberIfComplete(current)
            return false
        }

        return !PermissionMemory.completedSetupBefore
    }

    @MainActor
    static func openAccessibilitySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @MainActor
    static func openMicrophoneSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    @MainActor
    private static func openSystemSettingsPane(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
