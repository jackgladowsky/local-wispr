import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct InsertionTarget: Equatable {
    let processIdentifier: pid_t
    let appName: String
    let role: String?
    let subrole: String?
    let capturedAt: Date
}

enum InsertionOutcome: String {
    case pasted
    case copied
}

struct InsertionResult: Equatable {
    let outcome: InsertionOutcome
    let detail: String
    let restoredClipboard: Bool
}

@MainActor
final class InsertionController {
    private enum PasteboardConstants {
        static let pasteDelay: Duration = .milliseconds(100)
    }

    func captureTarget() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let focusedElement = focusedElement(for: app.processIdentifier)

        return InsertionTarget(
            processIdentifier: app.processIdentifier,
            appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown app",
            role: focusedElement.flatMap { attributeString($0, kAXRoleAttribute) },
            subrole: focusedElement.flatMap { attributeString($0, kAXSubroleAttribute) },
            capturedAt: Date()
        )
    }

    func insert(_ text: String, target: InsertionTarget?) async -> InsertionResult {
        let snapshot = PasteboardSnapshot.capture()
        copyToPasteboard(text)

        guard isStillFocusedOnTarget(target) else {
            return .init(
                outcome: .copied,
                detail: "Focus changed — press ⌘V to paste manually",
                restoredClipboard: false
            )
        }

        let pasteboard = NSPasteboard.general
        let temporaryChangeCount = pasteboard.changeCount

        if Self.isAccessibilityTrusted {
            if isSecureTargetCurrentFocus() {
                return .init(
                    outcome: .copied,
                    detail: "Secure field detected — press ⌘V if intended",
                    restoredClipboard: false
                )
            }

            postPasteShortcut()
        } else {
            switch await PasteHelperController.paste() {
            case .pasted:
                break
            case .secureTarget:
                return .init(
                    outcome: .copied,
                    detail: "Secure field detected — press ⌘V if intended",
                    restoredClipboard: false
                )
            case .needsPermission:
                return .init(
                    outcome: .copied,
                    detail: "Copied — enable Accessibility for auto-paste",
                    restoredClipboard: false
                )
            case .notInstalled:
                return .init(
                    outcome: .copied,
                    detail: "Copied — paste helper not installed",
                    restoredClipboard: false
                )
            case .failed:
                return .init(
                    outcome: .copied,
                    detail: "Copied — paste helper unavailable",
                    restoredClipboard: false
                )
            }
        }
        try? await Task.sleep(for: PasteboardConstants.pasteDelay)

        let restored = restorePreviousClipboardIfStillTemporary(
            snapshot,
            temporaryText: text,
            temporaryChangeCount: temporaryChangeCount
        )

        return .init(
            outcome: .pasted,
            detail: restored ? "Clipboard restored" : "Clipboard left unchanged",
            restoredClipboard: restored
        )
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    static func requestAccessibilityTrustPrompt() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func isStillFocusedOnTarget(_ target: InsertionTarget?) -> Bool {
        guard let target else { return true }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    private func isSecureTargetCurrentFocus() -> Bool {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let element = focusedElement(for: app.processIdentifier)
        else {
            return false
        }

        let values = [
            attributeString(element, kAXRoleAttribute),
            attributeString(element, kAXSubroleAttribute),
            attributeString(element, kAXDescriptionAttribute)
        ].compactMap { $0?.lowercased() }

        return values.contains { value in
            value.contains("secure") || value.contains("password")
        }
    }

    private func focusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        guard result == .success else { return nil }
        return value as? String
    }

    private func postPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func restorePreviousClipboardIfStillTemporary(
        _ snapshot: PasteboardSnapshot,
        temporaryText: String,
        temporaryChangeCount: Int
    ) -> Bool {
        let pasteboard = NSPasteboard.general

        guard
            pasteboard.changeCount == temporaryChangeCount,
            pasteboard.string(forType: .string) == temporaryText
        else {
            return false
        }

        snapshot.restore()
        return true
    }
}
