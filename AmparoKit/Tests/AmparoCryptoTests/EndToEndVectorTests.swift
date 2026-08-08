import Foundation
import Testing
import AmparoCrypto

/// M1-T5: the whole §6 chain exactly as the app will run it — enrollment
/// inputs to decrypted cipher fields — asserted against plaintexts the
/// official `bw` CLI produced for the same server data. Uses only the public
/// AmparoCrypto API.
@Suite struct EndToEndVectorTests {
    @Test func unlockDecryptsEveryFixtureCipher() throws {
        let vectors = try Vectors.load()

        let keys = try AccountUnlock.unlock(
            email: vectors.account.email,
            password: vectors.account.password,
            kdfIterations: vectors.account.kdfIterations,
            protectedUserKey: try EncString(parsing: vectors.account.protectedUserKey),
            encryptedPrivateKey: try EncString(parsing: vectors.account.encryptedPrivateKey)
        )
        #expect(keys.userKey.keyData.hex == vectors.account.userKeyHex)

        let orgKey = try keys.organizationKey(from: try EncString(parsing: vectors.organization.encKey))
        #expect(orgKey.keyData.hex == vectors.organization.orgKeyHex)

        // Both key paths (§6.4): organizationId == nil → user key, else org key.
        #expect(vectors.ciphers.contains { $0.organizationId == nil })
        #expect(vectors.ciphers.contains { $0.organizationId == vectors.organization.id })
        #expect(vectors.ciphers.contains { $0.totp != nil })

        for cipher in vectors.ciphers {
            let key = cipher.organizationId == nil ? keys.userKey : orgKey
            let fields: [(Vectors.Field?, String)] = [
                (cipher.name, "name"), (cipher.username, "username"),
                (cipher.password, "password"), (cipher.uri, "uri"), (cipher.totp, "totp"),
            ]
            for (field, label) in fields {
                guard let field else { continue }
                let decrypted = try EncString(parsing: field.enc).decryptString(with: key)
                #expect(decrypted == field.expected, "\(cipher.name.expected).\(label)")
            }
        }
    }
}
