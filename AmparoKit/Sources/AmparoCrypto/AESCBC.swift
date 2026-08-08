import CommonCrypto
import Foundation

/// AES-256-CBC with PKCS#7 padding via CommonCrypto (§6.2).
enum AESCBC {
    static func decrypt(key: Data, iv: Data, ciphertext: Data) throws -> Data {
        try crypt(CCOperation(kCCDecrypt), key: key, iv: iv, input: ciphertext)
    }

    static func encrypt(key: Data, iv: Data, plaintext: Data) throws -> Data {
        try crypt(CCOperation(kCCEncrypt), key: key, iv: iv, input: plaintext)
    }

    private static func crypt(_ operation: CCOperation, key: Data, iv: Data, input: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw AmparoCryptoError.invalidKeyLength(expected: kCCKeySizeAES256, got: key.count)
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw AmparoCryptoError.malformedEncString
        }
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = output.withUnsafeMutableBytes { outputPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    input.withUnsafeBytes { inputPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inputPtr.baseAddress, input.count,
                            outputPtr.baseAddress, outputPtr.count,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw AmparoCryptoError.cryptoOperationFailed("CCCrypt status \(status)")
        }
        return Data(output.prefix(written))
    }
}
