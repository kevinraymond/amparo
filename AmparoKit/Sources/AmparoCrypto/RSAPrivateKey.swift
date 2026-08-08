import Foundation
import Security

/// The account RSA-2048 private key, arriving as PKCS#8 DER inside a type-2
/// EncString (§6.1). Unwraps EncString types 3/4 (org keys, §6.2).
public struct RSAPrivateKey: Sendable {
    private let pkcs1Der: Data

    /// `SecKeyCreateWithData` expects PKCS#1 (`RSAPrivateKey`) DER, but the
    /// protocol delivers PKCS#8 (`PrivateKeyInfo`), so the outer structure is
    /// peeled off here:
    /// `SEQUENCE { version INTEGER, AlgorithmIdentifier SEQUENCE, privateKey OCTET STRING }`.
    public init(pkcs8Der: Data) throws {
        let outer = try DER.sequence(pkcs8Der)
        var cursor = outer
        let version = try DER.next(&cursor)
        guard version.tag == 0x02 else { throw AmparoCryptoError.invalidPrivateKey }
        let algorithm = try DER.next(&cursor)
        guard algorithm.tag == 0x30, algorithm.value.starts(with: DER.rsaEncryptionOID) else {
            throw AmparoCryptoError.invalidPrivateKey
        }
        let keyOctets = try DER.next(&cursor)
        guard keyOctets.tag == 0x04 else { throw AmparoCryptoError.invalidPrivateKey }
        self.pkcs1Der = keyOctets.value
    }

    private func secKey() throws -> SecKey {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1Der as CFData, attributes as CFDictionary, &error) else {
            throw AmparoCryptoError.invalidPrivateKey
        }
        return key
    }

    /// Decrypts EncString types 3 (OAEP-SHA256) and 4 (OAEP-SHA1).
    public func decrypt(_ encString: EncString) throws -> Data {
        let (ciphertext, algorithm): (Data, SecKeyAlgorithm)
        switch encString {
        case .rsaOaepSha256(let ct): (ciphertext, algorithm) = (ct, .rsaEncryptionOAEPSHA256)
        case .rsaOaepSha1(let ct): (ciphertext, algorithm) = (ct, .rsaEncryptionOAEPSHA1)
        case .deprecatedRsaHmac(let type, _, _): throw AmparoCryptoError.deprecatedEncType(type)
        case .aesCbc256Legacy, .aesCbc256HmacSha256: throw AmparoCryptoError.keyTypeMismatch
        }
        var error: Unmanaged<CFError>?
        guard let plaintext = SecKeyCreateDecryptedData(try secKey(), algorithm, ciphertext as CFData, &error) else {
            let message = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown"
            throw AmparoCryptoError.cryptoOperationFailed("RSA decrypt: \(message)")
        }
        return plaintext as Data
    }
}

/// Minimal DER reader — just enough to unwrap PKCS#8 (nothing else parses
/// ASN.1 in this codebase; a dependency isn't warranted for one structure).
enum DER {
    /// DER encoding of OID 1.2.840.113549.1.1.1 (rsaEncryption), tag+len+value.
    static let rsaEncryptionOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])

    struct TLV {
        let tag: UInt8
        let value: Data
    }

    /// Reads one TLV at the start of `data` and advances `data` past it.
    static func next(_ data: inout Data) throws -> TLV {
        guard data.count >= 2 else { throw AmparoCryptoError.invalidPrivateKey }
        let tag = data[data.startIndex]
        var index = data.index(after: data.startIndex)
        var length = Int(data[index])
        index = data.index(after: index)
        if length & 0x80 != 0 {
            let lengthBytes = length & 0x7F
            guard lengthBytes > 0, lengthBytes <= 4, data.distance(from: index, to: data.endIndex) >= lengthBytes else {
                throw AmparoCryptoError.invalidPrivateKey
            }
            length = 0
            for _ in 0..<lengthBytes {
                length = length << 8 | Int(data[index])
                index = data.index(after: index)
            }
        }
        guard data.distance(from: index, to: data.endIndex) >= length else {
            throw AmparoCryptoError.invalidPrivateKey
        }
        let end = data.index(index, offsetBy: length)
        let value = Data(data[index..<end])
        data = Data(data[end...])
        return TLV(tag: tag, value: value)
    }

    /// Requires `data` to be a single top-level SEQUENCE; returns its contents.
    static func sequence(_ data: Data) throws -> Data {
        var cursor = data
        let tlv = try next(&cursor)
        guard tlv.tag == 0x30, cursor.isEmpty else { throw AmparoCryptoError.invalidPrivateKey }
        return tlv.value
    }
}
