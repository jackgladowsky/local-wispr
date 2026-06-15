import Combine
import Foundation

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var snapshot = PanelSnapshot(
        phase: .idle,
        title: "Local Wispr",
        subtitle: "Ready",
        showsSpinner: false
    )
}
