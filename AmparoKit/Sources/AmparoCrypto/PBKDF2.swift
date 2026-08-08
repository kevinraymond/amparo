import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256 via CommonCrypto (CryptoKit offers no PBKDF2).
enum PBKDF2 {
    static func sha256(password: Data, salt: Data, iterations: Int, outputByteCount: Int) throws -> Data {
        var output = Data(count: outputByteCount)
        let status = output.withUnsafeMutableBytes { outputPtr in
            password.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.bindMemory(to: Int8.self).baseAddress, password.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        outputPtr.bindMemory(to: UInt8.self).baseAddress, outputByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw AmparoCryptoError.keyDerivationFailed }
        return output
    }
}
