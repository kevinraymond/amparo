import Foundation
import Testing
@testable import AmparoCrypto

/// M1-T3: wire-format parse/serialize, MAC-then-decrypt, tamper and fuzz.
@Suite struct EncStringTests {
    let key = try! SymmetricCryptoKey(data: Data(hex: String(repeating: "0123456789abcdef", count: 8)))

    // MARK: Parse / serialize

    @Test func parseSerializeRoundtripsAllTypes() throws {
        let samples = [
            "0.aXZpdml2aXZpdml2aXY=|Y3RjdGN0Y3RjdGN0Y3Rj",
            "2.aXZpdml2aXZpdml2aXY=|Y3RjdGN0Y3RjdGN0Y3Rj|bWFjbWFjbWFjbWFjbWFj",
            "3.Y3RjdGN0Y3RjdGN0Y3Rj",
            "4.Y3RjdGN0Y3RjdGN0Y3Rj",
            "5.Y3RjdGN0Y3RjdGN0Y3Rj|bWFjbWFjbWFjbWFjbWFj",
            "6.Y3RjdGN0Y3RjdGN0Y3Rj|bWFjbWFjbWFjbWFjbWFj",
        ]
        for sample in samples {
            let parsed = try EncString(parsing: sample)
            #expect(parsed.serialized() == sample)
        }
        #expect(try EncString(parsing: samples[0]).isLegacy)
        #expect(try !EncString(parsing: samples[1]).isLegacy)
    }

    @Test func realVectorParses() throws {
        let vectors = try Vectors.load()
        let parsed = try EncString(parsing: vectors.account.protectedUserKey)
        #expect(parsed.type == 2)
        #expect(parsed.serialized() == vectors.account.protectedUserKey)
        #expect(try EncString(parsing: vectors.organization.encKey).type == 4)
    }

    @Test(arguments: [
        "",
        "2",
        "2.",
        ".aXZ=|Y3Q=|bWFj",
        "2.aXZpdml2aXZpdml2aXY=",                          // too few parts
        "2.a|b",                                           // bad b64 + too few
        "2.aXZpdml2aXZpdml2aXY=|Y3RjdGN0Y3RjdGN0Y3Rj|bWFjbWFjbWFjbWFjbWFj|ZXh0cmE=", // too many
        "0.aXZpdml2aXZpdml2aXY=",                          // type 0 needs 2
        "3.Y3Q=|bWFj",                                     // type 3 needs 1
        "2.!!!|###|$$$",                                   // not base64
        "2.aXZpdml2aXZpdml2aXY=||bWFjbWFjbWFjbWFjbWFj",    // empty part
        "notanumber.aXZ=|Y3Q=|bWFj",
        "-2.aXZpdml2aXZpdml2aXY=|Y3RjdGN0Y3RjdGN0Y3Rj",
    ])
    func malformedInputsThrow(_ input: String) {
        #expect(throws: AmparoCryptoError.self) { try EncString(parsing: input) }
    }

    @Test func unknownTypesThrowUnknown() {
        // Type 1 (AES-128, pre-2017) is deliberately outside the §6.2 table.
        for (input, expected) in [
            ("1.aXZ2aXZpdml2aXZpdg==|Y3RjdGN0Y3RjdGN0Y3Rj", 1),
            ("7.YWJjZA==", 7),
            ("99.YWJjZA==", 99),
        ] {
            #expect(throws: AmparoCryptoError.unknownEncType(expected)) {
                try EncString(parsing: input)
            }
        }
    }

    // MARK: Encrypt / decrypt

    @Test func encryptDecryptRoundtrip() throws {
        for size in [0, 1, 15, 16, 17, 1024] {
            let plaintext = Data((0..<size).map { UInt8($0 % 251) })
            let enc = try EncString.encrypt(plaintext, with: key)
            #expect(enc.type == 2)
            #expect(try enc.decrypt(with: key) == plaintext)
            // …and through the wire format:
            #expect(try EncString(parsing: enc.serialized()).decrypt(with: key) == plaintext)
        }
    }

    @Test func decryptRealVector() throws {
        let vectors = try Vectors.load()
        let stretched = try SymmetricCryptoKey(
            encKey: Data(hex: vectors.account.stretchedEncKeyHex),
            macKey: Data(hex: vectors.account.stretchedMacKeyHex)
        )
        let userKey = try EncString(parsing: vectors.account.protectedUserKey).decrypt(with: stretched)
        #expect(userKey.hex == vectors.account.userKeyHex)
    }

    @Test func tamperedPartsFailMacBeforeDecrypt() throws {
        let enc = try EncString.encrypt(Data("segredo".utf8), with: key)
        guard case .aesCbc256HmacSha256(let iv, let ct, let mac) = enc else {
            Issue.record("expected type 2"); return
        }
        var flippedIv = iv; flippedIv[0] ^= 0x01
        var flippedCt = ct; flippedCt[flippedCt.count / 2] ^= 0x01
        var flippedMac = mac; flippedMac[mac.count - 1] ^= 0x01
        let tampered: [EncString] = [
            .aesCbc256HmacSha256(iv: flippedIv, ciphertext: ct, mac: mac),
            .aesCbc256HmacSha256(iv: iv, ciphertext: flippedCt, mac: mac),
            .aesCbc256HmacSha256(iv: iv, ciphertext: ct, mac: flippedMac),
        ]
        for encString in tampered {
            #expect(throws: AmparoCryptoError.macMismatch) { try encString.decrypt(with: key) }
        }
    }

    @Test func wrongKeyFailsMac() throws {
        let enc = try EncString.encrypt(Data("segredo".utf8), with: key)
        let otherKey = try SymmetricCryptoKey(data: Data(hex: String(repeating: "fe", count: 64)))
        #expect(throws: AmparoCryptoError.macMismatch) { try enc.decrypt(with: otherKey) }
    }

    @Test func legacyType0DecryptsWithoutMac() throws {
        let plaintext = Data("dado antigo".utf8)
        let iv = Data(hex: String(repeating: "0f", count: 16))
        let ct = try AESCBC.encrypt(key: key.encKey, iv: iv, plaintext: plaintext)
        let legacy = EncString.aesCbc256Legacy(iv: iv, ciphertext: ct)
        #expect(legacy.isLegacy)
        #expect(try legacy.decrypt(with: key) == plaintext)
    }

    @Test func deprecatedTypesRefuseDecrypt() throws {
        let enc = try EncString(parsing: "5.Y3RjdGN0Y3RjdGN0Y3Rj|bWFjbWFjbWFjbWFjbWFj")
        #expect(throws: AmparoCryptoError.deprecatedEncType(5)) { try enc.decrypt(with: key) }
    }

    @Test func symmetricDecryptOfRsaTypeIsKeyTypeMismatch() throws {
        let enc = try EncString(parsing: "4.Y3RjdGN0Y3RjdGN0Y3Rj")
        #expect(throws: AmparoCryptoError.keyTypeMismatch) { try enc.decrypt(with: key) }
    }

    // MARK: SymmetricCryptoKey

    @Test func keyLengthIsValidated() {
        #expect(throws: AmparoCryptoError.invalidKeyLength(expected: 64, got: 32)) {
            try SymmetricCryptoKey(data: Data(count: 32))
        }
        #expect(throws: AmparoCryptoError.invalidKeyLength(expected: 32, got: 16)) {
            try SymmetricCryptoKey(encKey: Data(count: 16), macKey: Data(count: 32))
        }
    }

    @Test func keySplitsIntoHalves() throws {
        let key = try SymmetricCryptoKey(data: Data(hex: String(repeating: "aa", count: 32) + String(repeating: "bb", count: 32)))
        #expect(key.encKey == Data(hex: String(repeating: "aa", count: 32)))
        #expect(key.macKey == Data(hex: String(repeating: "bb", count: 32)))
        #expect(key.keyData.count == 64)
    }
}
