import CryptoKit
import Foundation

/// RFC 5869 §2.3 **Expand** step only.
///
/// The Bitwarden-protocol stretched master key treats the master key itself
/// as the PRK (handoff §6.1). CryptoKit's `HKDF` always runs Extract+Expand,
/// which would derive a different PRK — so the Expand loop is implemented
/// directly: T(i) = HMAC-SHA256(PRK, T(i-1) ‖ info ‖ i).
public enum HKDF {
    public static func expand(prk: Data, info: Data, outputByteCount: Int) -> Data {
        precondition(
            outputByteCount > 0 && outputByteCount <= 255 * SHA256.byteCount,
            "RFC 5869: L must be in 1...255*HashLen"
        )
        let key = SymmetricKey(data: prk)
        var okm = Data()
        var block = Data()
        var counter: UInt8 = 1
        while okm.count < outputByteCount {
            var hmac = CryptoKit.HMAC<SHA256>(key: key)
            hmac.update(data: block)
            hmac.update(data: info)
            hmac.update(data: Data([counter]))
            block = Data(hmac.finalize())
            okm.append(block)
            counter += 1
        }
        return Data(okm.prefix(outputByteCount))
    }

    public static func expand(prk: Data, info: String, outputByteCount: Int) -> Data {
        expand(prk: prk, info: Data(info.utf8), outputByteCount: outputByteCount)
    }
}
