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
            .secondary
        case .listening:
            .red
        case .transcribing:
            .blue
        case .polishing:
            .teal
        case .inserted:
            .green
        case .copied:
            .indigo
        case .canceled:
            .orange
        case .error:
            .yellow
        }
    }
}

struct PanelSnapshot: Equatable {
    let phase: PanelPhase
    let title: String
    let subtitle: String
    let showsSpinner: Bool
}
