@testable import LocalWisprCore
import Foundation
import Testing

@Test
func moonshineServerControllerUsesConfiguredRuntimeAndDefaultEndpoint() throws {
    let scriptURL = try temporaryScriptURL()
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = MoonshineServerController.makeDefault(environment: [
        "LOCAL_WISPR_MOONSHINE_PYTHON": "/bin/sh",
        "LOCAL_WISPR_MOONSHINE_SERVER_SCRIPT": scriptURL.path
    ])

    #expect(controller?.engine.endpoint.absoluteString == "http://127.0.0.1:8179/transcribe")
}

@Test
func moonshineServerControllerCanDisableManagedSidecarOnly() throws {
    let scriptURL = try temporaryScriptURL()
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = MoonshineServerController.makeDefault(environment: [
        "LOCAL_WISPR_DISABLE_MANAGED_MOONSHINE_SERVER": "1",
        "LOCAL_WISPR_MOONSHINE_PYTHON": "/bin/sh",
        "LOCAL_WISPR_MOONSHINE_SERVER_SCRIPT": scriptURL.path,
        "LOCAL_WISPR_MOONSHINE_SERVER_URL": "http://127.0.0.1:8179/transcribe"
    ])

    #expect(controller == nil)
}

@Test
func moonshineServerControllerRejectsNonLoopbackEndpoint() throws {
    let scriptURL = try temporaryScriptURL()
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = MoonshineServerController.makeDefault(environment: [
        "LOCAL_WISPR_MOONSHINE_PYTHON": "/bin/sh",
        "LOCAL_WISPR_MOONSHINE_SERVER_SCRIPT": scriptURL.path,
        "LOCAL_WISPR_MOONSHINE_SERVER_URL": "http://192.168.1.50:8179/transcribe"
    ])

    #expect(controller == nil)
}

private func temporaryScriptURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalWisprCoreTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appendingPathComponent("moonshine_server.py")
    try Data("#!/usr/bin/env python3\n".utf8).write(to: scriptURL)
    return scriptURL
}
