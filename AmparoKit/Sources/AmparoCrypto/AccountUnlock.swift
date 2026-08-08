import Foundation

/// The decrypted key set for an account, produced once per unlock and used
/// for every subsequent cipher decryption (user-key path and org-key path).
public struct AccountKeys: Sendable {
    public let userKey: SymmetricCryptoKey
    public let privateKey: RSAPrivateKey

    /// Org Symmetric Key: EncString type 4 from `profile.organizations[].key`,
    /// unwrapped with the account private key (§6.1).
    public func organizationKey(from encKey: EncString) throws -> SymmetricCryptoKey {
        try SymmetricCryptoKey(data: try privateKey.decrypt(encKey))
    }
}

/// The full §6.1 unlock chain, from enrollment inputs to usable keys:
/// master key → stretched key → user key → private key.
public enum AccountUnlock {
    public static func unlock(
        email: String,
        password: String,
        kdfIterations: Int,
        protectedUserKey: EncString,
        encryptedPrivateKey: EncString
    ) throws -> AccountKeys {
        let masterKey = try MasterKey.derive(password: password, email: email, kdfIterations: kdfIterations)
        let stretched = try MasterKey.stretch(masterKey)
        let userKey = try SymmetricCryptoKey(data: try protectedUserKey.decrypt(with: stretched))
        let privateKey = try RSAPrivateKey(pkcs8Der: try encryptedPrivateKey.decrypt(with: userKey))
        return AccountKeys(userKey: userKey, privateKey: privateKey)
    }
}
