import AppKit
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var permissionSnapshot: PermissionSupport.Snapshot
    @Published private(set) var engineLines: [String]

    let whisperModelPath: String
    let logPath: String

    private let logger: TimingLogger

    init(logger: TimingLogger) {
        self.logger = logger
        permissionSnapshot = PermissionSupport.snapshot
        engineLines = EngineRegistry.statusLines()
        whisperModelPath = LocalWisprPaths.defaultWhisperModelURL.path
        logPath = logger.logURL.path
        PermissionMemory.rememberIfComplete(permissionSnapshot)
    }

    func refresh() {
        permissionSnapshot = PermissionSupport.snapshot
        engineLines = EngineRegistry.statusLines()
        PermissionMemory.rememberIfComplete(permissionSnapshot)
    }

    func openAccessibility() {
        InsertionController.requestAccessibilityTrustPrompt()
        PermissionSupport.openAccessibilitySettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    func requestMicrophone() {
        Task { [weak self] in
            let granted = await AudioCapture.requestMicrophoneAccessIfNeeded()

            await MainActor.run {
                if !granted {
                    PermissionSupport.openMicrophoneSettings()
                }

                self?.refresh()
            }
        }
    }

    func openLogs() {
        NSWorkspace.shared.open(logger.logURL)
    }

    func openAppSupport() {
        NSWorkspace.shared.open(LocalWisprPaths.applicationSupportDirectory)
    }
}
