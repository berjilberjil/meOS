import Foundation
import LocalAuthentication

/// Optional Touch ID app lock. The preference is device-local (UserDefaults),
/// not synced — it's a per-device security choice.
enum BiometricLock {
    static let key = "myos.touchIDLock"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "biometrics"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Prompt for biometric (falls back to device password). Returns success.
    ///
    /// Fails CLOSED. It used to return true when the policy could not be
    /// evaluated, so a user who enabled the lock and later removed their device
    /// passcode — which also drops Face ID enrolment — got an app that opened
    /// with no authentication at all. The same call gates revealing hidden
    /// notes, so those opened untouched too.
    static func authenticate(reason: String = "Unlock meOS") async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
