import Foundation
import LocalAuthentication

/// Face ID / Touch ID with device-passcode fallback. Locks when the app goes to the background.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked = false
    private var isAuthenticating = false

    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfEnabled(_ enabled: Bool) {
        if enabled { isLocked = true }
    }

    func unlockIfNeeded(enabled: Bool) {
        guard enabled else { isLocked = false; return }
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let context = LAContext()
        context.localizedCancelTitle = L10n.t("lock.cancel")
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L10n.t("lock.reason")) { success, _ in
            Task { @MainActor in
                self.isAuthenticating = false
                if success { self.isLocked = false }
            }
        }
    }

    /// Used when the user turns the toggle on, to confirm Face ID works before enabling it.
    static func confirm(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { completion(false); return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L10n.t("lock.reason")) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
