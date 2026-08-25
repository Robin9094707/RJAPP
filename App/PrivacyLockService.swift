import Foundation
import LocalAuthentication

@MainActor
final class PrivacyLockService: ObservableObject {
    static let shared = PrivacyLockService()

    @Published private(set) var isUnlocked = true
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "rjlove.biometric-lock")
            if !isEnabled { isUnlocked = true }
        }
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "rjlove.biometric-lock")
        isUnlocked = !isEnabled
    }

    func lock() {
        if isEnabled { isUnlocked = false }
    }

    @discardableResult
    func unlock() async -> Bool {
        guard isEnabled else { isUnlocked = true; return true }
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = false
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Öffne eure privaten RJ-Love-Inhalte."
            )
            isUnlocked = success
            return success
        } catch {
            isUnlocked = false
            return false
        }
    }

    func enableAfterAuthentication() async -> Bool {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Aktiviere den privaten App-Schutz für RJ Love."
            )
            if success {
                isEnabled = true
                isUnlocked = true
            }
            return success
        } catch {
            return false
        }
    }
}
