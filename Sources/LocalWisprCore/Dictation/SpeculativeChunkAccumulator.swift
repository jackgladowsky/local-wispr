import Foundation

struct SpeculativeTranscriptChunk: Equatable, Sendable {
    let index: Int
    let rawText: String
    let cleanedText: String?
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct SpeculativeChunkAccumulator: Equatable, Sendable {
    private var chunksByIndex: [Int: SpeculativeTranscriptChunk] = [:]

    mutating func record(_ chunk: SpeculativeTranscriptChunk) {
        chunksByIndex[chunk.index] = chunk
    }

    var isEmpty: Bool {
        chunksByIndex.isEmpty
    }

    var orderedChunks: [SpeculativeTranscriptChunk] {
        chunksByIndex.keys.sorted().compactMap { chunksByIndex[$0] }
    }

    func rawTranscript() -> Transcript? {
        let chunks = orderedChunks
        let text = Self.joinDeduplicatingOverlap(chunks.map(\.rawText))
        guard !text.isEmpty else { return nil }

        return Transcript(
            text: text,
            confidence: nil,
            segments: chunks.map {
                TranscriptSegment(text: $0.rawText, startTime: $0.startTime, endTime: $0.endTime)
            }
        )
    }

    func speculativeCleanedDraft() -> String {
        let texts = orderedChunks.map { chunk in
            let cleaned = chunk.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned?.isEmpty == false ? cleaned! : chunk.rawText
        }

        return Self.joinDeduplicatingOverlap(texts)
    }

    static func joinDeduplicatingOverlap(_ texts: [String], maxOverlapWords: Int = 8) -> String {
        texts.reduce("") { partialResult, next in
            merge(partialResult, next, maxOverlapWords: maxOverlapWords)
        }
    }

    private static func merge(_ first: String, _ second: String, maxOverlapWords: Int) -> String {
        let left = normalizedSpacing(first)
        let right = normalizedSpacing(second)

        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        let leftWords = left.split(separator: " ").map(String.init)
        let rightWords = right.split(separator: " ").map(String.init)
        let maxCandidate = min(maxOverlapWords, leftWords.count, rightWords.count)

        if maxCandidate > 0 {
            for count in stride(from: maxCandidate, through: 1, by: -1) {
                let suffix = leftWords.suffix(count).map(normalizedToken)
                let prefix = rightWords.prefix(count).map(normalizedToken)
                if suffix == prefix {
                    return (leftWords + rightWords.dropFirst(count)).joined(separator: " ")
                }
            }
        }

        return "\(left) \(right)"
    }

    private static func normalizedSpacing(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
