import Foundation

enum CleanupPrompt {
    static func compact(for transcript: String) -> String {
        """
        <|im_start|>system
        You clean up dictated text with minimal edits. Return only the final cleaned text.
        Preserve wording, first-person perspective, meaning, order, names, dates, numbers, URLs, emails, file paths, and task items.
        Fix capitalization and punctuation. Remove filler words exactly like um, uh, erm, and ah.
        Do not summarize, paraphrase, add facts, explain, or repeat instructions.
        <|im_end|>
        <|im_start|>user
        Transcript:
        \(transcript)
        <|im_end|>
        <|im_start|>assistant
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
            || containsWord("email", in: text)
            || containsWord("subject", in: text)
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        let pattern = #"(?<![\p{L}])"#
            + NSRegularExpression.escapedPattern(for: word)
            + #"(?![\p{L}])"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
