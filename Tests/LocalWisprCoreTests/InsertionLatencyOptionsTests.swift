@testable import LocalWisprCore
import Foundation
import Testing

@Test
func insertionLatencyOptionsUseClipboardSafeDefaults() {
    let options = InsertionLatencyOptions.current(environment: [:])

    #expect(options.pasteRestoreDelayMilliseconds == InsertionLatencyOptions.defaultPasteRestoreDelayMilliseconds)
    #expect(options.pasteRestoreDelay == .milliseconds(100))
    #expect(options.skipsClipboardRestore == false)
}

@Test
func insertionLatencyOptionsRequireExplicitUnsafeSkipRestoreFlag() {
    let enabled = InsertionLatencyOptions.current(environment: [
        InsertionLatencyOptions.unsafeSkipClipboardRestoreKey: "yes"
    ])
    let disabled = InsertionLatencyOptions.current(environment: [
        InsertionLatencyOptions.unsafeSkipClipboardRestoreKey: "0"
    ])

    #expect(enabled.skipsClipboardRestore)
    #expect(disabled.skipsClipboardRestore == false)
}

@Test
func insertionLatencyOptionsAcceptExplicitUnsafeRestoreDelay() {
    let options = InsertionLatencyOptions.current(environment: [
        InsertionLatencyOptions.unsafeRestoreDelayKey: "12"
    ])

    #expect(options.pasteRestoreDelayMilliseconds == 12)
    #expect(options.pasteRestoreDelay == .milliseconds(12))
}

@Test
func insertionLatencyOptionsIgnoreInvalidUnsafeRestoreDelay() {
    let negative = InsertionLatencyOptions.current(environment: [
        InsertionLatencyOptions.unsafeRestoreDelayKey: "-1"
    ])
    let nonnumeric = InsertionLatencyOptions.current(environment: [
        InsertionLatencyOptions.unsafeRestoreDelayKey: "fast"
    ])

    #expect(negative.pasteRestoreDelayMilliseconds == InsertionLatencyOptions.defaultPasteRestoreDelayMilliseconds)
    #expect(nonnumeric.pasteRestoreDelayMilliseconds == InsertionLatencyOptions.defaultPasteRestoreDelayMilliseconds)
}
