import Foundation

/// Every Keychain slot the app and the autofill extension share (§7.3),
/// with its protection class baked in. Two tiers:
///
/// - **Biometry-protected** (`.biometryCurrentSet` +
///   passcode-set-this-device-only): any read triggers Face ID — that IS the
///   unlock UX; there is no lock screen in the app. Re-enrolling Face ID
///   permanently invalidates these items (detected as
///   `VaultStatus.biometryInvalidated` → call-caregiver).
/// - **Passcode-only**: readable without biometry so background
///   refresh/sync can run.
public enum KeychainItem: String, CaseIterable, Sendable {
    // Biometry-protected key material.
    case userKey            // 64-byte User Symmetric Key
    case privateKey         // PKCS#8 DER
    case orgKeys            // JSON: orgId → base64 64-byte org key
    // Passcode-only operational state.
    case refreshToken
    case serverURL
    case email
    case deviceIdentifier   // UUID string, stable per enrollment (§6.3)
    case caregiverProfile   // JSON: display name + phone for the call screen
    case caregiverPIN       // JSON: salt + SHA-256(salt‖PIN)
    case consentRecord      // JSON: §10.3 attestation (timestamp, caregiver name)

    var isBiometryProtected: Bool {
        switch self {
        case .userKey, .privateKey, .orgKeys: true
        default: false
        }
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case userCancelledAuth
    case authenticationFailed
    case accessControlCreationFailed
    case unhandled(OSStatus)
}
