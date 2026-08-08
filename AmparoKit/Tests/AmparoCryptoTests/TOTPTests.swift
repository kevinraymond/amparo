import Foundation
import Testing
@testable import AmparoCrypto

@Suite("TOTP")
struct TOTPTests {
    // RFC 6238 Appendix B seeds: the ASCII digit sequence sized per algorithm.
    private static let sha1Seed = Data("12345678901234567890".utf8)
    private static let sha256Seed = Data("12345678901234567890123456789012".utf8)
    private static let sha512Seed = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    @Test(arguments: [
        (59.0, "94287082", "46119246", "90693936"),
        (1_111_111_109.0, "07081804", "68084774", "25091201"),
        (1_111_111_111.0, "14050471", "67062674", "99943326"),
        (1_234_567_890.0, "89005924", "91819424", "93441116"),
        (2_000_000_000.0, "69279037", "90698825", "38618901"),
        (20_000_000_000.0, "65353130", "77737706", "47863826"),
    ])
    func rfc6238AppendixBVectors(time: Double, sha1: String, sha256: String, sha512: String) {
        let date = Date(timeIntervalSince1970: time)
        #expect(TOTPGenerator(secret: Self.sha1Seed, algorithm: .sha1, digits: 8).code(at: date) == sha1)
        #expect(TOTPGenerator(secret: Self.sha256Seed, algorithm: .sha256, digits: 8).code(at: date) == sha256)
        #expect(TOTPGenerator(secret: Self.sha512Seed, algorithm: .sha512, digits: 8).code(at: date) == sha512)
    }

    @Test(arguments: [
        ("", ""), ("MY======", "f"), ("MZXQ====", "fo"), ("MZXW6===", "foo"),
        ("MZXW6YQ=", "foob"), ("MZXW6YTB", "fooba"), ("MZXW6YTBOI======", "foobar"),
        ("mzxw6ytboi", "foobar"),
    ])
    func base32Rfc4648Vectors(encoded: String, plain: String) {
        #expect(Data(base32: encoded) == Data(plain.utf8))
    }

    @Test func base32RejectsInvalidCharacters() {
        #expect(Data(base32: "1NVALID!") == nil)
    }

    /// The fixture cipher's decrypted totp field; expected codes computed
    /// with an independent Node-stdlib implementation (behavioral
    /// cross-check, same pattern as the M1 vectors).
    @Test func fixtureBareBase32FieldGeneratesKnownCodes() throws {
        let generator = try #require(TOTPGenerator(field: "JBSWY3DPEHPK3PXP"))
        #expect(generator.algorithm == .sha1)
        #expect(generator.digits == 6)
        #expect(generator.period == 30)
        #expect(generator.code(at: Date(timeIntervalSince1970: 59)) == "996554")
        #expect(generator.code(at: Date(timeIntervalSince1970: 1_111_111_109)) == "071271")
    }

    @Test func parsesOtpauthURIWithParameters() throws {
        let uri = "otpauth://totp/Example:member%40amparo.test"
            + "?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=7&period=60"
        let generator = try #require(TOTPGenerator(field: uri))
        #expect(generator.algorithm == .sha256)
        #expect(generator.digits == 7)
        #expect(generator.period == 60)
        #expect(generator.secret == Data(base32: "JBSWY3DPEHPK3PXP"))
    }

    @Test(arguments: [
        "otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP",  // counter-based: not ours
        "otpauth://totp/x?secret=",
        "otpauth://totp/x",
        "not base32 !!!",
        "",
    ])
    func unusableFieldsAreNil(field: String) {
        #expect(TOTPGenerator(field: field) == nil)
    }

    @Test func secondsRemainingDrivesTheCountdownRing() {
        let generator = TOTPGenerator(secret: Data("x".utf8))
        #expect(generator.secondsRemaining(at: Date(timeIntervalSince1970: 0)) == 30)
        #expect(generator.secondsRemaining(at: Date(timeIntervalSince1970: 29)) == 1)
        #expect(generator.secondsRemaining(at: Date(timeIntervalSince1970: 30)) == 30)
    }
}
