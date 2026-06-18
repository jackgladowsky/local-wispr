import SwiftUI

enum PanelPhase: String {
    case idle
    case listening
    case transcribing
    case polishing
    case inserted
    case copied
    case canceled
    case error

    var systemImageName: String {
        switch self {
        case .idle:
            "waveform"
        case .listening:
            "mic.fill"
        case .transcribing:
            "waveform.badge.magnifyingglass"
        case .polishing:
            "sparkles"
        case .inserted:
            "text.insert"
        case .copied:
            "doc.on.clipboard"
        case .canceled:
            "xmark"
        case .error:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            Color(red: 0.50, green: 0.54, blue: 0.60)
        case .listening:
            Color(red: 0.20, green: 0.58, blue: 0.96)
        case .transcribing:
            Color(red: 0.30, green: 0.50, blue: 0.92)
        case .polishing:
            Color(red: 0.34, green: 0.70, blue: 0.80)
        case .inserted:
            Color(red: 0.24, green: 0.70, blue: 0.36)
        case .copied:
            Color(red: 0.42, green: 0.40, blue: 0.82)
        case .canceled:
            Color(red: 0.88, green: 0.50, blue: 0.22)
        case .error:
            Color(red: 0.92, green: 0.32, blue: 0.28)
        }
    }
}

struct PanelSnapshot: Equatable {
    let phase: PanelPhase
    let title: String
    let subtitle: String
    let showsSpinner: Bool
}
