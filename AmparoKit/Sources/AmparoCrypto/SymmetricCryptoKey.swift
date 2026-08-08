import Foundation

/// A 64-byte symmetric key in the Bitwarden-protocol convention (§6.1):
/// first 32 bytes AES-256-CBC encryption key, last 32 bytes HMAC-SHA256 key.
public struct SymmetricCryptoKey: Equatable, Sendable {
    public let encKey: Data
    public let macKey: Data

    public init(encKey: Data, macKey: Data) throws {
        guard encKey.count == 32 else {
            throw AmparoCryptoError.invalidKeyLength(expected: 32, got: encKey.count)
        }
        guard macKey.count == 32 else {
            throw AmparoCryptoError.invalidKeyLength(expected: 32, got: macKey.count)
        }
        self.encKey = encKey
        self.macKey = macKey
    }

    /// Splits the 64-byte wire form (user key, org key).
    public init(data: Data) throws {
        guard data.count == 64 else {
            throw AmparoCryptoError.invalidKeyLength(expected: 64, got: data.count)
        }
        try self.init(
            encKey: Data(data.prefix(32)),
            macKey: Data(data.suffix(32))
        )
    }

    public var keyData: Data { encKey + macKey }
}
