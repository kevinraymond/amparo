import AmparoCrypto
import Foundation

/// `POST /identity/accounts/prelogin` (§6.1).
public struct PreloginResponse: Decodable, Equatable, Sendable {
    public let kdf: Int
    public let kdfIterations: Int
    public let kdfMemory: Int?
    public let kdfParallelism: Int?
}

/// The two OAuth artifacts with different custody rules (D12): the access
/// token stays in client memory; the refresh token is the caller's to
/// persist (M3 Keychain) and seed back in at init.
public struct TokenPair: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
}

/// `POST /identity/connect/token` success body (§6.3). `key`/`privateKey`
/// (delivered on the password grant) feed `AccountUnlock.unlock` at
/// enrollment. `refreshToken` is optional defensively: the refresh grant's
/// rotation behavior is asserted in the integration suite, and a missing
/// field must not fail the decode.
public struct TokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let key: EncString?
    public let privateKey: EncString?
    public let kdf: Int?
    public let kdfIterations: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case key, privateKey, kdf, kdfIterations
    }
}
