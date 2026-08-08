import Foundation
import Testing
@testable import AmparoCrypto

/// RFC 5869 Appendix A vectors, SHA-256 cases — Expand step only, using the
/// PRK values the RFC publishes for each case (M1-T1).
@Suite struct HKDFExpandRFC5869Tests {
    @Test func caseA1Basic() {
        let okm = HKDF.expand(
            prk: Data(hex: "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"),
            info: Data(hex: "f0f1f2f3f4f5f6f7f8f9"),
            outputByteCount: 42
        )
        #expect(okm.hex == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
    }

    @Test func caseA2LongerInputs() {
        let info = Data((0xb0...0xff).map { UInt8($0) })
        let okm = HKDF.expand(
            prk: Data(hex: "06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244"),
            info: info,
            outputByteCount: 82
        )
        #expect(okm.hex == "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87")
    }

    @Test func caseA3EmptyInfo() {
        let okm = HKDF.expand(
            prk: Data(hex: "19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04"),
            info: Data(),
            outputByteCount: 42
        )
        #expect(okm.hex == "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
    }

    /// The protocol derivation this exists for: "enc"/"mac" info strings must
    /// produce different 32-byte halves from one PRK (§6.1).
    @Test func encMacExpansionDiffers() {
        let prk = Data(hex: String(repeating: "ab", count: 32))
        let enc = HKDF.expand(prk: prk, info: "enc", outputByteCount: 32)
        let mac = HKDF.expand(prk: prk, info: "mac", outputByteCount: 32)
        #expect(enc.count == 32)
        #expect(mac.count == 32)
        #expect(enc != mac)
    }
}
