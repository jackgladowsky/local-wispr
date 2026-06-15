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
            microphone.isAllowed
        }

        var canAutoPasteFromMainApp: Bool {
            accessibility.isAllowed
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
        openSystemSettingsPane("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    @MainActor
    static func openMicrophoneSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
    }

    static var stableInstallWarning: String? {
        let stablePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent("Local Wispr.app")
            .standardizedFileURL
            .path
        let currentPath = Bundle.main.bundleURL.standardizedFileURL.path

        if currentPath == stablePath {
            return nil
        }

        if currentPath.contains("/dist/") {
            return "Running from dist/. Install to ~/Applications so macOS permissions stick across rebuilds."
        }

        return "Running from \(currentPath). For smoother permissions, use ~/Applications/Local Wispr.app."
    }

    @MainActor
    private static func openSystemSettingsPane(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
