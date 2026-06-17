import Foundation

/// Runtime knobs for insertion latency experiments.
///
/// Defaults preserve clipboard restoration behavior: Local Wispr waits before restoring so the
/// target app can consume the temporary pasteboard contents. Lower restore delays and skipping
/// restoration are intentionally exposed only through `LOCAL_WISPR_INSERT_UNSAFE_*` variables
/// because restoring too early can make the target paste the previous clipboard instead.
struct InsertionLatencyOptions: Equatable {
    static let defaultPasteRestoreDelayMilliseconds = 100
    static let unsafeSkipClipboardRestoreKey = "LOCAL_WISPR_INSERT_UNSAFE_SKIP_CLIPBOARD_RESTORE"
    static let unsafeRestoreDelayKey = "LOCAL_WISPR_INSERT_UNSAFE_RESTORE_DELAY_MS"

    let pasteRestoreDelayMilliseconds: Int
    let skipsClipboardRestore: Bool

    var pasteRestoreDelay: Duration {
        .milliseconds(pasteRestoreDelayMilliseconds)
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> InsertionLatencyOptions {
        let restoreDelay = nonnegativeInteger(
            environment[unsafeRestoreDelayKey]
        ) ?? defaultPasteRestoreDelayMilliseconds

        return InsertionLatencyOptions(
            pasteRestoreDelayMilliseconds: restoreDelay,
            skipsClipboardRestore: truthy(environment[unsafeSkipClipboardRestoreKey])
        )
    }

    private static func nonnegativeInteger(_ value: String?) -> Int? {
        guard
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            let intValue = Int(value),
            intValue >= 0
        else {
            return nil
        }

        return intValue
    }

    private static func truthy(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }
}
