import Foundation

struct AudioRecording: Sendable, Equatable {
    let rawURL: URL
    let wavURL: URL
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}
