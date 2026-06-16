@testable import LocalWisprCore
import Testing

@Test
func permissionStatusTitlesAreUserFacing() {
    #expect(PermissionSupport.StatusKind.allowed.title == "Allowed")
    #expect(PermissionSupport.StatusKind.actionRequired.title == "Action Required")
    #expect(PermissionSupport.StatusKind.notRequested.title == "Not Requested")
    #expect(PermissionSupport.StatusKind.restricted.title == "Restricted")
    #expect(PermissionSupport.StatusKind.unknown.title == "Unknown")
}

@Test
func permissionSnapshotCompletionRequiresMicrophoneOnly() {
    let snapshot = PermissionSupport.Snapshot(
        accessibility: .actionRequired,
        microphone: .allowed
    )

    #expect(snapshot.isComplete)
    #expect(!snapshot.canAutoPasteFromMainApp)
}

@Test
func permissionSnapshotAutoPasteRequiresAccessibility() {
    let snapshot = PermissionSupport.Snapshot(
        accessibility: .allowed,
        microphone: .notRequested
    )

    #expect(!snapshot.isComplete)
    #expect(snapshot.canAutoPasteFromMainApp)
}
