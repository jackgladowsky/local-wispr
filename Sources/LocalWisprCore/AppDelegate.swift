import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: DictationPanelController?
    private var hotkeyController: HotkeyController?
    private var session: DictationSession?
    private let settingsWindowController = SettingsWindowController()
    private let audioCapture = AudioCapture()
    private let logger = TimingLogger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelController = DictationPanelController()
        let insertionController = InsertionController()
        let session = DictationSession(
            panelController: panelController,
            audioCapture: audioCapture,
            sttEngine: EngineRegistry.makeSTTEngine(),
            rewriteEngine: EngineRegistry.makeRewriteEngine(),
            insertionController: insertionController,
            logger: logger
        )

        self.panelController = panelController
        self.session = session

        setupStatusItem()
        setupHotkey(for: session, panelController: panelController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak panelController] in
            guard let self, let panelController else { return }

            if !self.presentPermissionOnboardingIfNeeded() {
                panelController.show(
                    .init(
                        phase: .idle,
                        title: "Local Wispr ready",
                        subtitle: "Hold Control-Option-Space",
                        showsSpinner: false
                    ),
                    autoHideAfter: 1.8
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Local Wispr")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(menuItem("Simulate Dictation", action: #selector(simulateDictation)))
        menu.addItem(menuItem("Cancel", action: #selector(cancelDictation)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings...", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Permissions...", action: #selector(openSettings)))
        menu.addItem(menuItem("Retry Hotkey", action: #selector(retryHotkey)))
        menu.addItem(menuItem("Show Engine Status", action: #selector(showEngineStatus)))
        menu.addItem(menuItem("Reload Engines", action: #selector(reloadEngines)))
        menu.addItem(menuItem("Open Debug Log", action: #selector(openDebugLog)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Local Wispr", action: #selector(quit)))

        item.menu = menu
        statusItem = item
    }

    private func setupHotkey(for session: DictationSession, panelController: DictationPanelController) {
        let controller = HotkeyController(
            onStart: { [weak session] in
                Task { @MainActor in
                    session?.startRecording()
                }
            },
            onStop: { [weak session] in
                Task { @MainActor in
                    session?.stopRecording()
                }
            },
            onCancel: { [weak session] in
                Task { @MainActor in
                    session?.cancel()
                }
            }
        )

        hotkeyController = controller

        if !controller.start() {
            panelController.show(
                .init(
                    phase: .error,
                    title: "Hotkey unavailable",
                    subtitle: "Grant Accessibility permission from the menu",
                    showsSpinner: false
                ),
                autoHideAfter: 4.0
            )
        }
    }

    @discardableResult
    private func presentPermissionOnboardingIfNeeded() -> Bool {
        guard PermissionSupport.needsOnboarding else { return false }

        panelController?.show(
            .init(
                phase: .idle,
                title: "Finish setup",
                subtitle: "Use the Local Wispr settings window",
                showsSpinner: false
            ),
            autoHideAfter: 6.0
        )

        settingsWindowController.show(logger: logger)

        return true
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func simulateDictation() {
        session?.runMockDictation()
    }

    @objc private func cancelDictation() {
        session?.cancel()
    }

    @objc private func openSettings() {
        settingsWindowController.show(logger: logger)
    }

    @objc private func retryHotkey() {
        guard let session, let panelController else { return }
        hotkeyController?.stop()
        setupHotkey(for: session, panelController: panelController)

        if InsertionController.isAccessibilityTrusted {
            panelController.show(
                .init(
                    phase: .idle,
                    title: "Hotkey ready",
                    subtitle: "Hold Control-Option-Space",
                    showsSpinner: false
                ),
                autoHideAfter: 2.0
            )
        }
    }

    @objc private func showEngineStatus() {
        let lines = EngineRegistry.statusLines()
        panelController?.show(
            .init(
                phase: lines.first?.contains("not configured") == true ? .error : .idle,
                title: lines.first ?? "Engine status",
                subtitle: lines.dropFirst().first ?? "Cleanup: unavailable",
                showsSpinner: false
            ),
            autoHideAfter: 5.0
        )
    }

    @objc private func reloadEngines() {
        guard let panelController else { return }

        let insertionController = InsertionController()
        let session = DictationSession(
            panelController: panelController,
            audioCapture: audioCapture,
            sttEngine: EngineRegistry.makeSTTEngine(),
            rewriteEngine: EngineRegistry.makeRewriteEngine(),
            insertionController: insertionController,
            logger: logger
        )

        self.session = session
        hotkeyController?.stop()
        setupHotkey(for: session, panelController: panelController)
        showEngineStatus()
    }

    @objc private func openDebugLog() {
        NSWorkspace.shared.open(logger.logURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
