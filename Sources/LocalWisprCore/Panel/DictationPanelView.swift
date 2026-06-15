import SwiftUI

struct DictationPanelView: View {
    @ObservedObject var model: PanelViewModel

    var body: some View {
        let snapshot = model.snapshot

        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(snapshot.phase.tint.opacity(0.18))
                    .frame(width: 42, height: 42)

                Image(systemName: snapshot.phase.systemImageName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(snapshot.phase.tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(snapshot.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if snapshot.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 360, height: 82)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
