import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            permissions

            if let warning = model.installWarning {
                installWarning(warning)
            }

            Divider()

            engines

            Divider()

            footer
        }
        .padding(22)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.permissionSnapshot.isComplete ? "Local Wispr Ready" : "Finish Setup")
                    .font(.system(size: 20, weight: .semibold))

                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private var permissions: some View {
        VStack(spacing: 10) {
            permissionRow(
                icon: "mic",
                title: "Microphone",
                subtitle: "Required for local dictation",
                statusTitle: model.permissionSnapshot.microphone.title,
                isAllowed: model.permissionSnapshot.microphone.isAllowed,
                buttonTitle: model.permissionSnapshot.microphone.isAllowed ? "Open" : "Enable",
                action: model.requestMicrophone
            )

            permissionRow(
                icon: "hand.raised",
                title: "Main App Accessibility",
                subtitle: "Auto-paste from this build",
                statusTitle: model.permissionSnapshot.accessibility.title,
                isAllowed: model.permissionSnapshot.accessibility.isAllowed,
                buttonTitle: model.permissionSnapshot.accessibility.isAllowed ? "Open" : "Enable",
                action: model.openAccessibility
            )

            permissionRow(
                icon: "bolt.horizontal",
                title: "Paste Helper",
                subtitle: "Stable auto-paste across rebuilds",
                statusTitle: model.pasteHelperStatus.title,
                isAllowed: model.pasteHelperStatus.isTrusted,
                buttonTitle: model.pasteHelperButtonTitle,
                action: model.openPasteHelperAccessibility
            )
        }
    }

    private var headerSubtitle: String {
        if !model.permissionSnapshot.microphone.isAllowed {
            return "Approve microphone to start dictating."
        }

        if model.canAutoPaste {
            return "Dictation and auto-paste are ready."
        }

        return "Dictation works now; without Accessibility it will copy for manual ⌘V."
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        statusTitle: String,
        isAllowed: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isAllowed ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(statusTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAllowed ? .green : .secondary)
                .frame(width: 118, alignment: .trailing)

            Button(buttonTitle, action: action)
                .frame(width: 72)
                .disabled(buttonTitle == "Wait")
        }
        .padding(.vertical, 6)
    }

    private func installWarning(_ warning: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(warning)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var engines: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(model.engineLines, id: \.self) { line in
                let parts = split(line)
                GridRow {
                    Text(parts.label)
                        .foregroundStyle(.secondary)
                    Text(parts.value)
                }
            }

            GridRow {
                Text("Whisper model")
                    .foregroundStyle(.secondary)
                Text(model.whisperModelPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            GridRow {
                Text("Debug log")
                    .foregroundStyle(.secondary)
                Text(model.logPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 13))
    }

    private var footer: some View {
        HStack {
            Button {
                model.openLogs()
            } label: {
                Label("Log", systemImage: "doc.text")
            }

            Button {
                model.openAppSupport()
            } label: {
                Label("Models", systemImage: "folder")
            }

            Spacer()

            if model.permissionSnapshot.isComplete {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private func split(_ line: String) -> (label: String, value: String) {
        let parts = line.split(separator: ":", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        guard parts.count == 2 else {
            return ("Engine", line)
        }

        return (parts[0], parts[1])
    }
}
