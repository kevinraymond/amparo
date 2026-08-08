import Foundation

public enum AmparoCryptoError: Error, Equatable, Sendable {
    /// The EncString didn't match `{type}.{b64}|{b64}…` or a part wasn't valid Base64.
    case malformedEncString
    /// A type number outside the wire format we implement (§6.2 table).
    case unknownEncType(Int)
    /// Types 5/6 (RSA+HMAC): long-deprecated, never emitted by the servers we
    /// target; parsed for completeness but not decryptable.
    case deprecatedEncType(Int)
    /// HMAC verification failed — tampered or wrong key. Nothing was decrypted.
    case macMismatch
    /// The EncString type can't be decrypted with the key kind offered.
    case keyTypeMismatch
    case invalidKeyLength(expected: Int, got: Int)
    case invalidPrivateKey
    case keyDerivationFailed
    case cryptoOperationFailed(String)
}
