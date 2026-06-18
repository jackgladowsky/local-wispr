import AppKit
import SwiftUI

@MainActor
final class DictationPanelController {
    private let model = PanelViewModel()
    private let panel: NSPanel
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DictationPanelMetrics.size.width,
                height: DictationPanelMetrics.size.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: DictationPanelView(model: model))
        panel.alphaValue = 0
    }

    func show(_ snapshot: PanelSnapshot, autoHideAfter delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        model.snapshot = snapshot
        if snapshot.phase != .listening {
            model.audioLevels = Self.silentAudioLevels
        }
        positionPanel()

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        if let delay {
            let workItem = DispatchWorkItem { [weak self] in
                self?.hide()
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func updateAudioLevels(_ levels: [Float]) {
        guard model.snapshot.phase == .listening else { return }

        let targetLevels = Self.normalizedAudioLevels(levels)
        model.audioLevels = zip(model.audioLevels, targetLevels).map { current, target in
            let attack = Float(0.62)
            let release = Float(0.24)
            let blend = target > current ? attack : release
            return current + (target - current) * blend
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        model.audioLevels = Self.silentAudioLevels

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private static let silentAudioLevels = Array(repeating: Float(0), count: 9)

    private static func normalizedAudioLevels(_ levels: [Float]) -> [Float] {
        let clamped = levels.prefix(silentAudioLevels.count).map { min(max($0, 0), 1) }
        guard clamped.count < silentAudioLevels.count else { return Array(clamped) }
        return clamped + Array(repeating: Float(0), count: silentAudioLevels.count - clamped.count)
    }

    private func positionPanel() {
        guard let screen = screenForPanel() else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 4
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForPanel() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }
}
