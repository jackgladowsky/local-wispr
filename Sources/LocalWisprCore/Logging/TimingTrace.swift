import Foundation

final class TimingTrace {
    struct Mark: Equatable {
        let name: String
        let timestamp: UInt64
    }

    let id = UUID()
    private(set) var marks: [Mark] = []

    func mark(_ name: String) {
        marks.append(.init(name: name, timestamp: DispatchTime.now().uptimeNanoseconds))
    }

    func elapsedMilliseconds(from start: String, to end: String) -> Double? {
        guard
            let startMark = marks.first(where: { $0.name == start }),
            let endMark = marks.first(where: { $0.name == end }),
            endMark.timestamp >= startMark.timestamp
        else {
            return nil
        }

        return Double(endMark.timestamp - startMark.timestamp) / 1_000_000
    }
}
