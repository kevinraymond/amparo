import CryptoKit
import Foundation

/// RFC 6238 TOTP over RFC 4226 HOTP, implemented from the RFCs. Cipher
/// `totp` fields carry either a full `otpauth://` URI or a bare base32
/// secret (the fixtures use the latter); the member only ever sees the
/// resulting code (§7.4).
public struct TOTPGenerator: Equatable, Sendable {
    public enum Algorithm: String, Equatable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    public let secret: Data
    public let algorithm: Algorithm
    public let digits: Int
    public let period: Int

    public init(secret: Data, algorithm: Algorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// Parses a decrypted cipher `totp` field; nil means the field is not
    /// something we can generate codes from (hotp URIs, malformed base32).
    public init?(field: String) {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let components = URLComponents(string: trimmed),
                  components.host?.lowercased() == "totp" else { return nil }
            func query(_ name: String) -> String? {
                components.queryItems?.first { $0.name.lowercased() == name }?.value
            }
            guard let secret = query("secret").flatMap({ Data(base32: $0) }), !secret.isEmpty else {
                return nil
            }
            let digits = query("digits").flatMap(Int.init) ?? 6
            let period = query("period").flatMap(Int.init) ?? 30
            guard (6...8).contains(digits), period > 0 else { return nil }
            self.init(
                secret: secret,
                algorithm: query("algorithm").flatMap { Algorithm(rawValue: $0.uppercased()) } ?? .sha1,
                digits: digits,
                period: period
            )
        } else {
            guard let secret = Data(base32: trimmed), !secret.isEmpty else { return nil }
            self.init(secret: secret)
        }
    }

    public func code(at date: Date) -> String {
        var counter = UInt64(date.timeIntervalSince1970 / Double(period)).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: secret)
        let mac: Data
        switch algorithm {
        case .sha1: mac = Data(CryptoKit.HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Data(CryptoKit.HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Data(CryptoKit.HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        // RFC 4226 §5.3 dynamic truncation.
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let binary = (UInt32(mac[offset]) & 0x7f) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])
        let modulus = (0..<digits).reduce(UInt32(1)) { value, _ in value * 10 }
        return String(format: "%0\(digits)d", binary % modulus)
    }

    /// Seconds until the current code rolls over, in 1...period — drives the
    /// countdown ring.
    public func secondsRemaining(at date: Date) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }
}

extension Data {
    /// RFC 4648 base32; case-insensitive, padding optional.
    init?(base32 string: String) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup: [Character: UInt32] = [:]
        for (index, character) in alphabet.enumerated() {
            lookup[character] = UInt32(index)
        }
        var bits: UInt32 = 0
        var bitCount = 0
        var bytes: [UInt8] = []
        for character in string.uppercased() where character != "=" {
            guard let value = lookup[character] else { return nil }
            bits = bits << 5 | value
            bitCount += 5
            if bitCount >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: bits >> UInt32(bitCount - 8)))
                bitCount -= 8
            }
        }
        self.init(bytes)
    }
}
