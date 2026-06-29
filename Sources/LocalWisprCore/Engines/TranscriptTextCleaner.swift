import Foundation

enum TranscriptTextCleaner {
    private static let artifactTokens = [
        "blank_audio",
        "silence",
        "music",
        "noise",
        "inaudible",
        "applause",
        "laughter"
    ]

    static func cleanedTranscript(from text: String) -> String {
        var previousNormalizedLine: String?
        var cleanedLines: [String] = []

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            var line = stripANSIEscapeSequences(from: rawLine)
            line = line.replacingOccurrences(
                of: #"^\s*\[[0-9:.\-–>\s]+\]\s*"#,
                with: "",
                options: .regularExpression
            )
            line = removeKnownArtifactTokens(from: line)

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  !isDiagnosticLine(lowercased),
                  !isPunctuationOnly(trimmed)
            else { continue }

            let normalized = trimmed
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased()
            guard normalized != previousNormalizedLine else { continue }

            cleanedLines.append(trimmed)
            previousNormalizedLine = normalized
        }

        return cleanedLines
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripANSIEscapeSequences(from line: String) -> String {
        line.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    private static func removeKnownArtifactTokens(from line: String) -> String {
        var cleaned = line
        for token in artifactTokens {
            cleaned = cleaned.replacingOccurrences(
                of: #"(?i)(?:^|\s)[\[(]\s*"# + NSRegularExpression.escapedPattern(for: token) + #"\s*[\])]\s*(?=$|\s|[,.!?;:])"#,
                with: " ",
                options: .regularExpression
            )
        }
        return cleaned
    }

    private static func isDiagnosticLine(_ lowercasedTrimmedLine: String) -> Bool {
        lowercasedTrimmedLine.hasPrefix("moonshine_")
            || lowercasedTrimmedLine.hasPrefix("model:")
            || lowercasedTrimmedLine.hasPrefix("load_time")
            || lowercasedTrimmedLine.hasPrefix("system_info")
            || lowercasedTrimmedLine.contains("system_info")
            || lowercasedTrimmedLine.hasPrefix("{") && lowercasedTrimmedLine.contains("moonshine")
    }

    private static func isPunctuationOnly(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }
}
