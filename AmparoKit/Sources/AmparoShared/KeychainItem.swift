import Foundation

/// Every Keychain slot the app and the autofill extension share (§7.3),
/// with its protection class baked in. Two tiers:
///
/// - **Biometry-protected** (`.biometryCurrentSet` +
///   passcode-set-this-device-only): reading it triggers Face ID — that IS
///   the unlock UX; there is no lock screen in the app. All key material
///   lives in ONE blob because every biometry-gated read prompts separately
///   (D19: one blob = one Face ID per unlock). Re-enrolling Face ID
///   permanently invalidates it (detected as
///   `VaultStoreError.biometryInvalidated` → call-caregiver).
/// - **Passcode-only**: readable without biometry so background
///   refresh/sync can run.
public enum KeychainItem: String, CaseIterable, Sendable {
    /// JSON `VaultKeyMaterial`: user key + private key DER + org keys.
    case vaultKeys
    // Passcode-only operational state.
    case refreshToken
    case serverURL
    case email
    case deviceIdentifier   // UUID string, stable per enrollment (§6.3)
    case caregiverProfile   // JSON: display name + phone for the call screen
    case caregiverPIN       // JSON: salt + SHA-256(salt‖PIN)
    case consentRecord      // §10.3 attestation (timestamp, caregiver name)

    var isBiometryProtected: Bool {
        self == .vaultKeys
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case userCancelledAuth
    case authenticationFailed
    case accessControlCreationFailed
    case unhandled(OSStatus)
}
