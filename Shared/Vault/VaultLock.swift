import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID / passcode gate for the vault.
///
/// iCloud Keychain can't sync items that require biometrics at the OS level, so
/// this lock is enforced by Typo on top of the Keychain's own encryption. The vault
/// locks again 60 seconds after the app leaves the foreground, or immediately when
/// the user taps Lock.
@MainActor
@Observable
final class VaultLock {
    private(set) var isUnlocked = false
    private(set) var lastError: String?
    private var backgroundedAt: Date?
    static let relockAfter: TimeInterval = 60

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }

    func unlock() async {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = "Set a device passcode to use the vault."
            return
        }
        do {
            // .deviceOwnerAuthentication falls back to the passcode if biometrics fail.
            isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                          localizedReason: "Unlock your saved cards")
            lastError = nil
        } catch {
            isUnlocked = false
            if (error as? LAError)?.code != .userCancel { lastError = error.localizedDescription }
        }
    }

    func lock() { isUnlocked = false }

    func didEnterBackground() { backgroundedAt = .now }

    func didBecomeActive() {
        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) > Self.relockAfter { lock() }
        backgroundedAt = nil
    }
}
