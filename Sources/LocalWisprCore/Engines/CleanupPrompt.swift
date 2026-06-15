import Foundation

enum CleanupPrompt {
    static func compact(for transcript: String) -> String {
        """
        Clean up this dictated text. Fix punctuation/capitalization, remove obvious filler, preserve meaning, and return only the final text.

        Text: \(transcript)
        """
    }

    static func shouldUseFastLocalCleanup(for transcript: String) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }

        let maxCharacters = Int(ProcessInfo.processInfo.environment["LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS"] ?? "120") ?? 120
        guard maxCharacters > 0 else { return false }

        return text.count <= maxCharacters && !looksStructured(text)
    }

    private static func looksStructured(_ text: String) -> Bool {
        text.contains("\n")
            || text.contains(" bullet ")
            || text.contains(" list ")
            || text.contains(" numbered ")
            || text.contains(" email ")
            || text.contains(" subject ")
    }
}
