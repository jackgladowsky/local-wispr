import AppKit
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var permissionSnapshot: PermissionSupport.Snapshot
    @Published private(set) var pasteHelperStatus: PasteHelperController.Status
    @Published private(set) var engineLines: [String]

    let whisperModelPath: String
    let logPath: String
    let installWarning: String?

    private let logger: TimingLogger
    private var pasteHelperStatusTask: Task<Void, Never>?
    private var autoPastePollingTask: Task<Void, Never>?

    init(logger: TimingLogger) {
        self.logger = logger
        permissionSnapshot = PermissionSupport.snapshot
        pasteHelperStatus = PasteHelperController.isInstalled ? .checking : .notInstalled
        engineLines = EngineRegistry.statusLines()
        whisperModelPath = LocalWisprPaths.defaultWhisperModelURL.path
        logPath = logger.logURL.path
        installWarning = PermissionSupport.stableInstallWarning
        PermissionMemory.rememberIfComplete(permissionSnapshot)
        refreshPasteHelperStatus()
    }

    deinit {
        pasteHelperStatusTask?.cancel()
        autoPastePollingTask?.cancel()
    }

    var canAutoPaste: Bool {
        permissionSnapshot.canAutoPasteFromMainApp || pasteHelperStatus.isTrusted
    }

    var pasteHelperButtonTitle: String {
        switch pasteHelperStatus {
        case .checking:
            "Wait"
        case .notInstalled:
            "Find"
        case .needsPermission, .unavailable:
            "Enable"
        case .trusted:
            "Open"
        }
    }

    func refresh() {
        refreshPermissionSnapshot()
        engineLines = EngineRegistry.statusLines()
        refreshPasteHelperStatus()
    }

    func openAccessibility() {
        InsertionController.requestAccessibilityTrustPrompt()
        PermissionSupport.openAccessibilitySettings()
        startAutoPastePolling()
    }

    func openPasteHelperAccessibility() {
        guard PasteHelperController.isInstalled else {
            NSWorkspace.shared.open(Bundle.main.bundleURL.deletingLastPathComponent())
            return
        }

        Task { [weak self] in
            await PasteHelperController.requestTrustPrompt()
            PermissionSupport.openAccessibilitySettings()
            self?.startAutoPastePolling()
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

    private func refreshPermissionSnapshot() {
        permissionSnapshot = PermissionSupport.snapshot
        PermissionMemory.rememberIfComplete(permissionSnapshot)
    }

    private func refreshPasteHelperStatus() {
        pasteHelperStatusTask?.cancel()
        pasteHelperStatus = PasteHelperController.isInstalled ? .checking : .notInstalled

        guard PasteHelperController.isInstalled else { return }

        pasteHelperStatusTask = Task { [weak self] in
            let status = await PasteHelperController.checkStatus()
            guard !Task.isCancelled else { return }
            self?.pasteHelperStatus = status
        }
    }

    private func startAutoPastePolling() {
        autoPastePollingTask?.cancel()
        autoPastePollingTask = Task { [weak self] in
            for _ in 0..<180 {
                guard let self, !Task.isCancelled else { return }

                self.refreshPermissionSnapshot()
                let helperStatus = await PasteHelperController.checkStatus()
                guard !Task.isCancelled else { return }
                self.pasteHelperStatus = helperStatus

                if InsertionController.isAccessibilityTrusted || helperStatus.isTrusted {
                    NotificationCenter.default.post(name: .localWisprAutoPasteDidBecomeAvailable, object: nil)
                    return
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
