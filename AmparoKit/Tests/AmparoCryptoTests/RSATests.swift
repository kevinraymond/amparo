import Foundation
import Security
import Testing
@testable import AmparoCrypto

/// M1-T4: PKCS#8 unwrap and OAEP decrypt (types 3/4), org-key path.
@Suite struct RSATests {
    @Test func unwrapsOrgKeyType4FromVector() throws {
        let vectors = try Vectors.load()
        let privateKey = try RSAPrivateKey(pkcs8Der: Data(base64Encoded: vectors.account.privateKeyPkcs8B64)!)
        let orgKey = try privateKey.decrypt(try EncString(parsing: vectors.organization.encKey))
        #expect(orgKey.hex == vectors.organization.orgKeyHex)
        #expect(orgKey.count == 64)
    }

    /// Type 3 (OAEP-SHA256) has no server-produced fixture — Vaultwarden
    /// delivers org keys as type 4 — so roundtrip against our own private key.
    @Test func type3RoundtripAgainstOwnKey() throws {
        let vectors = try Vectors.load()
        let pkcs8 = Data(base64Encoded: vectors.account.privateKeyPkcs8B64)!

        var outer = try DER.sequence(pkcs8)
        _ = try DER.next(&outer) // version
        _ = try DER.next(&outer) // algorithm
        let pkcs1 = try DER.next(&outer).value
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        let secKey = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(secKey)!

        let plaintext = Data("mensagem para a chave publica".utf8)
        let ciphertext = SecKeyCreateEncryptedData(
            publicKey, .rsaEncryptionOAEPSHA256, plaintext as CFData, nil
        )! as Data

        let privateKey = try RSAPrivateKey(pkcs8Der: pkcs8)
        #expect(try privateKey.decrypt(.rsaOaepSha256(ciphertext: ciphertext)) == plaintext)
    }

    @Test func garbagePkcs8IsRejected() {
        for bad in [Data(), Data("not der at all".utf8), Data(hex: "300000"), Data(hex: "02010030")] {
            #expect(throws: AmparoCryptoError.invalidPrivateKey) { try RSAPrivateKey(pkcs8Der: bad) }
        }
    }

    @Test func rsaDecryptOfSymmetricTypeIsKeyTypeMismatch() throws {
        let vectors = try Vectors.load()
        let privateKey = try RSAPrivateKey(pkcs8Der: Data(base64Encoded: vectors.account.privateKeyPkcs8B64)!)
        let symmetric = try EncString(parsing: vectors.account.protectedUserKey)
        #expect(throws: AmparoCryptoError.keyTypeMismatch) { try privateKey.decrypt(symmetric) }
    }
}
