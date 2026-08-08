import Foundation
import Testing
@testable import AmparoCrypto

/// M1-T2: PBKDF2 primitives against RFC 7914 §11 vectors, then the full
/// email/password → master key → auth hash → stretched key chain against the
/// behavioral vectors (validated by the official CLI logging in with the
/// same derivation — see fixtures/gen-vectors.mjs).
@Suite struct MasterKeyTests {
    @Test func pbkdf2Sha256RFC7914Vector1() throws {
        let dk = try PBKDF2.sha256(
            password: Data("passwd".utf8), salt: Data("salt".utf8),
            iterations: 1, outputByteCount: 64
        )
        #expect(dk.hex == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
    }

    @Test func pbkdf2Sha256RFC7914Vector2() throws {
        let dk = try PBKDF2.sha256(
            password: Data("Password".utf8), salt: Data("NaCl".utf8),
            iterations: 80000, outputByteCount: 64
        )
        #expect(dk.hex == "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d")
    }

    @Test func fullChainMatchesBehavioralVectors() throws {
        let account = try Vectors.load().account
        #expect(account.kdf == 0)

        let masterKey = try MasterKey.derive(
            password: account.password, email: account.email, kdfIterations: account.kdfIterations
        )
        #expect(masterKey.hex == account.masterKeyHex)

        let hash = try MasterKey.authenticationHash(masterKey: masterKey, password: account.password)
        #expect(hash == account.masterPasswordHashB64)

        let stretched = try MasterKey.stretch(masterKey)
        #expect(stretched.encKey.hex == account.stretchedEncKeyHex)
        #expect(stretched.macKey.hex == account.stretchedMacKeyHex)
    }

    /// Salt is the *lowercased* email (§6.1) — mixed-case input must not
    /// change the derivation.
    @Test func emailIsLowercasedBeforeUse() throws {
        let account = try Vectors.load().account
        let masterKey = try MasterKey.derive(
            password: account.password,
            email: account.email.uppercased(),
            kdfIterations: account.kdfIterations
        )
        #expect(masterKey.hex == account.masterKeyHex)
    }
}
