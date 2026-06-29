import Foundation

struct RuleBasedRewriteEngine: RewriteEngine {
    let name = "Basic Local Cleanup"

    func rewrite(_ transcript: Transcript) async throws -> CleanedText {
        let cleaned = Self.cleanup(transcript.text)
        guard !cleaned.isEmpty else {
            throw LocalWisprError.emptyTranscript
        }
        return CleanedText(text: cleaned, engineName: name)
    }

    static func cleanup(_ input: String) -> String {
        var text = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let fillerPattern = #"(?i)\b(um+|uh+|erm+|ah+|you know|i mean)\b[,\s]*"#
        text = text.replacingOccurrences(of: fillerPattern, with: "", options: .regularExpression)

        text = applySpokenFormattingCommands(to: text)

        let replacements: [(String, String)] = [
            (#"(?i)\bi\b"#, "I"),
            (#"(?i)\bjohn\b"#, "John"),
            (#"(?i)\bfriday\b"#, "Friday"),
            (#"(?i)\bmonday\b"#, "Monday"),
            (#"(?i)\btuesday\b"#, "Tuesday"),
            (#"(?i)\bwednesday\b"#, "Wednesday"),
            (#"(?i)\bthursday\b"#, "Thursday"),
            (#"(?i)\bsaturday\b"#, "Saturday"),
            (#"(?i)\bsunday\b"#, "Sunday")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        text = normalizePunctuationSpacing(text)
        text = capitalizeSentences(text)

        if let last = text.last, !".!?".contains(last) {
            text += "."
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySpokenFormattingCommands(to input: String) -> String {
        var text = " \(input) "

        let punctuationCommands: [(String, String)] = [
            (#"(?i)(?<=\S)\s+comma\s+(?!(?:key|operator|character|word)\b)(?=\S)"#, ", "),
            (#"(?i)(?<=\S)\s+(?:period|full stop)\b\s*(?!(?:key|character|word)s?\b)(?=\S|$)"#, ". "),
            (#"(?i)(?<=\S)\s+question mark\b\s*(?!(?:key|character|word)s?\b)(?=\S|$)"#, "? "),
            (#"(?i)(?<=\S)\s+exclamation (?:point|mark)\b\s*(?!(?:key|character|word)s?\b)(?=\S|$)"#, "! "),
            (#"(?i)(?<=\S)\s+colon\b\s+(?!(?:key|character|word)\b)(?=\S)"#, ": "),
            (#"(?i)(?<=\S)\s+semicolon\b\s+(?!(?:key|character|word)\b)(?=\S)"#, "; "),
            (#"(?i)(?<=\S)\s+dash\b\s+(?!(?:key|character|word)\b)(?=\S)"#, " — ")
        ]

        for (pattern, replacement) in punctuationCommands {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        let lineBreakCommands: [(String, String)] = [
            (#"(?i)\s+new line\s+"#, "\n"),
            (#"(?i)\s+new paragraph\s+"#, "\n\n")
        ]
        for (pattern, replacement) in lineBreakCommands {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePunctuationSpacing(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,.!?;:])(\S)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"\s+—\s+"#, with: " — ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentences(_ input: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in input {
            if shouldCapitalize, character.isLetter {
                result.append(contentsOf: character.uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
            }

            if ".!?\n".contains(character) {
                shouldCapitalize = true
            } else if !character.isWhitespace {
                shouldCapitalize = false
            }
        }

        return result
    }
}
