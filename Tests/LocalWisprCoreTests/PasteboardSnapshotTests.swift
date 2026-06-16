@testable import LocalWisprCore
import AppKit
import Foundation
import Testing

@Test
@MainActor
func pasteboardSnapshotRestoresStringContents() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LocalWisprCoreTests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString("original text", forType: .string)

    let snapshot = PasteboardSnapshot.capture(from: pasteboard)

    pasteboard.clearContents()
    pasteboard.setString("temporary text", forType: .string)
    snapshot.restore(to: pasteboard)

    #expect(pasteboard.string(forType: .string) == "original text")
}

@Test
@MainActor
func pasteboardSnapshotCapturesMultipleRepresentations() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LocalWisprCoreTests.\(UUID().uuidString)"))
    let item = NSPasteboardItem()
    item.setString("plain", forType: .string)
    item.setString("<b>plain</b>", forType: .html)

    pasteboard.clearContents()
    pasteboard.writeObjects([item])

    let snapshot = PasteboardSnapshot.capture(from: pasteboard)

    #expect(snapshot.items.count == 1)
    #expect(snapshot.items[0].representations.contains { $0.type == .string })
    #expect(snapshot.items[0].representations.contains { $0.type == .html })
}
