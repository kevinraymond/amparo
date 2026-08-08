import Foundation

/// The §6.1 master-key chain. All inputs come from enrollment (email,
/// master password) and prelogin (kdf parameters); PBKDF2 only — Argon2id is
/// out of scope until P4 (handoff D3) and must be rejected upstream.
public enum MasterKey {
    /// Master Key (32B): PBKDF2-SHA256(password, salt = lowercased email).
    public static func derive(password: String, email: String, kdfIterations: Int) throws -> Data {
        try PBKDF2.sha256(
            password: Data(password.utf8),
            salt: Data(email.lowercased().utf8),
            iterations: kdfIterations,
            outputByteCount: 32
        )
    }

    /// Master Password Hash (auth): PBKDF2-SHA256(masterKey, salt = password,
    /// 1 iteration), Base64 — sent as `password` in the token request, never
    /// used as key material.
    public static func authenticationHash(masterKey: Data, password: String) throws -> String {
        try PBKDF2.sha256(
            password: masterKey,
            salt: Data(password.utf8),
            iterations: 1,
            outputByteCount: 32
        ).base64EncodedString()
    }

    /// Stretched Master Key (64B): HKDF-Expand(PRK = masterKey) with info
    /// "enc" / "mac" — unlocks the protected user key from token/sync.
    public static func stretch(_ masterKey: Data) throws -> SymmetricCryptoKey {
        try SymmetricCryptoKey(
            encKey: HKDF.expand(prk: masterKey, info: "enc", outputByteCount: 32),
            macKey: HKDF.expand(prk: masterKey, info: "mac", outputByteCount: 32)
        )
    }
}
