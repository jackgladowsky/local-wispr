import SwiftUI

enum DictationPanelMetrics {
    static let size = CGSize(width: 82, height: 36)
}

struct DictationPanelView: View {
    @ObservedObject var model: PanelViewModel

    var body: some View {
        let snapshot = model.snapshot

        MacLikeDictationIndicator(snapshot: snapshot, audioLevels: model.audioLevels)
            .frame(width: DictationPanelMetrics.size.width, height: DictationPanelMetrics.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(snapshot.title))
            .accessibilityValue(Text(snapshot.subtitle))
    }
}

private struct MacLikeDictationIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: PanelSnapshot
    let audioLevels: [Float]

    var body: some View {
        TimelineView(.animation) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let isListening = snapshot.phase == .listening
            let isActive = isListening || snapshot.showsSpinner
            let pulse = isActive ? CGFloat((sin(time * 2.8) + 1) / 2) : 0
            let cornerRadius = DictationPanelMetrics.size.height / 2

            ZStack {
                VisualEffectBackground()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.16),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if isActive {
                    Capsule()
                        .fill(snapshot.phase.tint.opacity(0.07 + Double(pulse) * 0.025))
                        .frame(width: 58 + pulse * 5, height: 22 + pulse * 2)
                        .blur(radius: 10)
                }

                StatusMark(snapshot: snapshot, time: time, audioLevels: audioLevels)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 44, height: 1)
                    .padding(.top, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06),
                                snapshot.phase.tint.opacity(isActive ? 0.16 + Double(pulse) * 0.05 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 6)
            .shadow(color: snapshot.phase.tint.opacity(isActive ? 0.04 + Double(pulse) * 0.025 : 0.02), radius: 8, x: 0, y: 3)
        }
    }
}

private struct StatusMark: View {
    let snapshot: PanelSnapshot
    let time: TimeInterval
    let audioLevels: [Float]

    var body: some View {
        ZStack {
            switch snapshot.phase {
            case .listening:
                ListeningWaveform(levels: audioLevels)
            case .transcribing, .polishing:
                ProcessingDots(time: time)
            case .inserted, .copied:
                CheckmarkShape()
                    .stroke(
                        Color.white.opacity(0.92),
                        style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 14, height: 10)
            case .canceled:
                XMark()
            case .error:
                WarningMark()
            case .idle:
                IdleMark(tint: snapshot.phase.tint)
            }
        }
    }
}

private struct ListeningWaveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3.2) {
            ForEach(0..<9, id: \.self) { index in
                let rawLevel = index < levels.count ? levels[index] : 0
                let level = CGFloat(min(max(rawLevel, 0), 1))
                let easedLevel = 1 - pow(1 - level, 1.8)

                Capsule()
                    .fill(Color.white.opacity(0.58 + Double(easedLevel) * 0.34))
                    .frame(width: 2.8, height: 4 + easedLevel * 15)
            }
        }
        .animation(.interactiveSpring(response: 0.08, dampingFraction: 0.70), value: levels)
    }
}

private struct ProcessingDots: View {
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 3.2) {
            ForEach(0..<3, id: \.self) { index in
                let wave = (sin(time * 4.0 + Double(index) * 1.1) + 1) / 2

                Circle()
                    .fill(Color.white.opacity(0.48 + wave * 0.38))
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(0.86 + CGFloat(wave) * 0.18)
            }
        }
    }
}

private struct IdleMark: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.76))
            .frame(width: 15, height: 2.6)
            .overlay {
                Capsule()
                    .fill(Color.white.opacity(0.24))
            }
    }
}

private struct XMark: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: 14, height: 2)
                .rotationEffect(.degrees(45))
            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: 14, height: 2)
                .rotationEffect(.degrees(-45))
        }
    }
}

private struct WarningMark: View {
    var body: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: 2.2, height: 7.5)
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 2.6, height: 2.6)
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.10))
        return path
    }
}
