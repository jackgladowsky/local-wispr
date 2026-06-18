import Foundation

enum TranscriptTextCleaner {
    static func cleanedTranscript(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*\[[^\]]+\]\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty
                    && !trimmed.hasPrefix("moonshine_")
                    && !trimmed.lowercased().contains("system_info")
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
