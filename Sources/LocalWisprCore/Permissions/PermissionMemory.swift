import Foundation

enum PermissionMemory {
    private static let completedSetupKey = "permissions.completedSetup"
    private static let completedSetupDateKey = "permissions.completedSetupDate"

    static var completedSetupBefore: Bool {
        UserDefaults.standard.bool(forKey: completedSetupKey)
    }

    static func rememberIfComplete(_ snapshot: PermissionSupport.Snapshot) {
        guard snapshot.isComplete else { return }

        UserDefaults.standard.set(true, forKey: completedSetupKey)
        UserDefaults.standard.set(Date(), forKey: completedSetupDateKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedSetupKey)
        UserDefaults.standard.removeObject(forKey: completedSetupDateKey)
    }
}
