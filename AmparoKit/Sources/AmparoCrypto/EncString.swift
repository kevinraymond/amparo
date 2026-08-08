import CryptoKit
import Foundation

/// The `{encType}.{b64 part}|{b64 part}…` wire format (§6.2).
///
/// | Type | Scheme                          | Parts      |
/// |------|---------------------------------|------------|
/// | 0    | AES-256-CBC (legacy, no MAC)    | iv\|ct     |
/// | 2    | AES-256-CBC + HMAC-SHA256       | iv\|ct\|mac|
/// | 3    | RSA-2048-OAEP-SHA256            | ct         |
/// | 4    | RSA-2048-OAEP-SHA1              | ct         |
/// | 5/6  | RSA + HMAC (deprecated)         | ct\|mac    |
///
/// Types 5/6 parse but refuse to decrypt (`deprecatedEncType`) — the servers
/// we target never emit them and there is no test data to validate against.
public enum EncString: Equatable, Sendable {
    case aesCbc256Legacy(iv: Data, ciphertext: Data)
    case aesCbc256HmacSha256(iv: Data, ciphertext: Data, mac: Data)
    case rsaOaepSha256(ciphertext: Data)
    case rsaOaepSha1(ciphertext: Data)
    case deprecatedRsaHmac(type: Int, ciphertext: Data, mac: Data)

    public var type: Int {
        switch self {
        case .aesCbc256Legacy: 0
        case .aesCbc256HmacSha256: 2
        case .rsaOaepSha256: 3
        case .rsaOaepSha1: 4
        case .deprecatedRsaHmac(let type, _, _): type
        }
    }

    /// Legacy type 0 has no MAC; callers should surface a warning and treat
    /// the data as decrypt-only (§6.2).
    public var isLegacy: Bool {
        if case .aesCbc256Legacy = self { return true }
        return false
    }

    // MARK: Parse / serialize

    public init(parsing string: String) throws {
        guard let dot = string.firstIndex(of: "."), dot != string.startIndex else {
            throw AmparoCryptoError.malformedEncString
        }
        guard let type = Int(string[string.startIndex..<dot]) else {
            throw AmparoCryptoError.malformedEncString
        }
        let parts = try string[string.index(after: dot)...]
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { part -> Data in
                guard let data = Data(base64Encoded: String(part)), !data.isEmpty else {
                    throw AmparoCryptoError.malformedEncString
                }
                return data
            }
        switch (type, parts.count) {
        case (0, 2): self = .aesCbc256Legacy(iv: parts[0], ciphertext: parts[1])
        case (2, 3): self = .aesCbc256HmacSha256(iv: parts[0], ciphertext: parts[1], mac: parts[2])
        case (3, 1): self = .rsaOaepSha256(ciphertext: parts[0])
        case (4, 1): self = .rsaOaepSha1(ciphertext: parts[0])
        case (5, 2), (6, 2): self = .deprecatedRsaHmac(type: type, ciphertext: parts[0], mac: parts[1])
        case (0, _), (2, _), (3, _), (4, _), (5, _), (6, _):
            throw AmparoCryptoError.malformedEncString
        default:
            throw AmparoCryptoError.unknownEncType(type)
        }
    }

    public func serialized() -> String {
        let parts: [Data]
        switch self {
        case .aesCbc256Legacy(let iv, let ct): parts = [iv, ct]
        case .aesCbc256HmacSha256(let iv, let ct, let mac): parts = [iv, ct, mac]
        case .rsaOaepSha256(let ct), .rsaOaepSha1(let ct): parts = [ct]
        case .deprecatedRsaHmac(_, let ct, let mac): parts = [ct, mac]
        }
        return "\(type)." + parts.map { $0.base64EncodedString() }.joined(separator: "|")
    }

    // MARK: Symmetric decrypt/encrypt

    /// Decrypts types 0 and 2. Type 2 verifies the HMAC (over iv‖ct, §6.2)
    /// in constant time **before** any decryption; type 0 has no MAC and
    /// decrypts with the enc half only.
    public func decrypt(with key: SymmetricCryptoKey) throws -> Data {
        switch self {
        case .aesCbc256Legacy(let iv, let ct):
            return try AESCBC.decrypt(key: key.encKey, iv: iv, ciphertext: ct)
        case .aesCbc256HmacSha256(let iv, let ct, let mac):
            // isValidAuthenticationCode is CryptoKit's constant-time compare.
            guard CryptoKit.HMAC<SHA256>.isValidAuthenticationCode(
                mac, authenticating: iv + ct, using: SymmetricKey(data: key.macKey)
            ) else { throw AmparoCryptoError.macMismatch }
            return try AESCBC.decrypt(key: key.encKey, iv: iv, ciphertext: ct)
        case .rsaOaepSha256, .rsaOaepSha1:
            throw AmparoCryptoError.keyTypeMismatch
        case .deprecatedRsaHmac(let type, _, _):
            throw AmparoCryptoError.deprecatedEncType(type)
        }
    }

    /// Convenience for the common case: decrypt and decode UTF-8.
    public func decryptString(with key: SymmetricCryptoKey) throws -> String {
        guard let string = String(data: try decrypt(with: key), encoding: .utf8) else {
            throw AmparoCryptoError.cryptoOperationFailed("plaintext is not valid UTF-8")
        }
        return string
    }

    /// Produces a type 2 EncString (fresh random IV).
    public static func encrypt(_ plaintext: Data, with key: SymmetricCryptoKey) throws -> EncString {
        var iv = Data(count: 16)
        let status = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else {
            throw AmparoCryptoError.cryptoOperationFailed("SecRandomCopyBytes status \(status)")
        }
        let ct = try AESCBC.encrypt(key: key.encKey, iv: iv, plaintext: plaintext)
        let mac = Data(CryptoKit.HMAC<SHA256>.authenticationCode(for: iv + ct, using: SymmetricKey(data: key.macKey)))
        return .aesCbc256HmacSha256(iv: iv, ciphertext: ct, mac: mac)
    }
}
