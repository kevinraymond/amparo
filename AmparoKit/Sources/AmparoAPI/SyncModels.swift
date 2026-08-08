import AmparoCrypto
import Foundation

/// `GET /api/sync?excludeDomains=true` (§6.4). We consume `profile` and
/// `ciphers`; everything else the server sends is ignored. Ciphers are
/// lossy-decoded (a bad element is dropped, not fatal); `profile` decodes
/// strictly because an account without keys is unusable.
public struct SyncResponse: Decodable, Sendable {
    public let profile: Profile
    public let ciphers: [Cipher]

    /// v1 consumes Login ciphers only (§6.4); trashed ones are excluded.
    public var loginCiphers: [Cipher] {
        ciphers.filter { $0.type == 1 && $0.deletedDate == nil }
    }

    enum CodingKeys: String, CodingKey {
        case profile, ciphers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(Profile.self, forKey: .profile)
        ciphers = try container.decodeIfPresent(LossyArray<Cipher>.self, forKey: .ciphers)?.elements ?? []
    }
}

/// The key material half of the sync payload: everything
/// `AccountUnlock.unlock` and `AccountKeys.organizationKey(from:)` need.
public struct Profile: Decodable, Sendable {
    public let id: String
    public let email: String?
    public let key: EncString
    public let privateKey: EncString
    public let organizations: [ProfileOrganization]

    enum CodingKeys: String, CodingKey {
        case id, email, key, privateKey, organizations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        key = try container.decode(EncString.self, forKey: .key)
        privateKey = try container.decode(EncString.self, forKey: .privateKey)
        organizations = try container.decodeIfPresent([ProfileOrganization].self, forKey: .organizations) ?? []
    }
}

/// `profile.organizations[]` — only the org key matters (type 4 EncString,
/// unwrapped via `AccountKeys.organizationKey(from:)`).
public struct ProfileOrganization: Codable, Equatable, Sendable {
    public let id: String
    public let key: EncString?
}

/// Cipher as received — every secret field stays an EncString until the app
/// decrypts it on demand (§7.3). Key selection: `organizationId == nil` →
/// user key, else org key (§6.4). Trash is `deletedDate` (observed; §6.4
/// corrected from `deleted?`). Dates stay strings until M3 needs them.
/// Codable both ways: decoded from sync, re-encoded into the local §7.3
/// store (ciphers persist encrypted as received).
public struct Cipher: Codable, Equatable, Sendable {
    public let id: String
    public let organizationId: String?
    public let type: Int
    public let name: EncString?
    public let login: LoginData?
    public let revisionDate: String?
    public let deletedDate: String?
}

public struct LoginData: Codable, Equatable, Sendable {
    public let username: EncString?
    public let password: EncString?
    public let totp: EncString?
    public let uris: [LoginURI]?
}

public struct LoginURI: Codable, Equatable, Sendable {
    public let uri: EncString?
    public let match: Int?
}
