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

        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = capitalizeSentences(text)

        if let last = text.last, !".!?".contains(last) {
            text += "."
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

            if ".!?".contains(character) {
                shouldCapitalize = true
            } else if !character.isWhitespace {
                shouldCapitalize = false
            }
        }

        return result
    }
}
