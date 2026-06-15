import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private enum ExitCode {
    static let success: Int32 = 0
    static let needsPermission: Int32 = 2
    static let secureTarget: Int32 = 3
    static let usage: Int32 = 64
}

private let rawArguments = Array(CommandLine.arguments.dropFirst())
private let argumentSet = Set(rawArguments)

private var responseFileURL: URL? {
    guard let index = rawArguments.firstIndex(of: "--response-file") else { return nil }
    let valueIndex = rawArguments.index(after: index)
    guard rawArguments.indices.contains(valueIndex) else { return nil }
    return URL(fileURLWithPath: rawArguments[valueIndex])
}

private var isTrustedForPaste: Bool {
    AXIsProcessTrusted() || CGPreflightPostEventAccess()
}

@MainActor
private func finish(_ response: String, code: Int32) -> Never {
    if let responseFileURL {
        try? response.write(to: responseFileURL, atomically: true, encoding: .utf8)
    }

    exit(code)
}

private func requestAccessibilityPrompt() {
    let options = [
        "AXTrustedCheckOptionPrompt": true
    ] as CFDictionary

    _ = AXIsProcessTrustedWithOptions(options)
    _ = CGRequestPostEventAccess()
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

if argumentSet.contains("--request-permission") {
    requestAccessibilityPrompt()
    Thread.sleep(forTimeInterval: 0.75)
    finish(
        isTrustedForPaste ? "trusted" : "needsPermission",
        code: isTrustedForPaste ? ExitCode.success : ExitCode.needsPermission
    )
}

if argumentSet.contains("--check") {
    finish(
        isTrustedForPaste ? "trusted" : "needsPermission",
        code: isTrustedForPaste ? ExitCode.success : ExitCode.needsPermission
    )
}

if argumentSet.contains("--paste") {
    guard isTrustedForPaste else {
        finish("needsPermission", code: ExitCode.needsPermission)
    }

    guard !isSecureTargetCurrentFocus() else {
        finish("secureTarget", code: ExitCode.secureTarget)
    }

    postPasteShortcut()
    finish("pasted", code: ExitCode.success)
}

requestAccessibilityPrompt()
finish(isTrustedForPaste ? "trusted" : "usage", code: isTrustedForPaste ? ExitCode.success : ExitCode.usage)
