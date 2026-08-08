import AmparoAPI
import AmparoCrypto
import CryptoKit
import Foundation
import Security

public enum VaultStoreError: Error, Equatable, Sendable {
    case notEnrolled
    /// Face ID was re-enrolled: `.biometryCurrentSet` items are permanently
    /// gone while the passcode-tier enrollment markers remain. Terminal —
    /// purge and route to call-caregiver (§7.3).
    case biometryInvalidated
    case storeCorrupted
    case incompleteServerData(String)
}

public struct CaregiverProfile: Codable, Equatable, Sendable {
    public let name: String
    public let phone: String

    public init(name: String, phone: String) {
        self.name = name
        self.phone = phone
    }
}

/// §10.3 consent attestation, stored locally and never exported.
public struct ConsentRecord: Codable, Equatable, Sendable {
    public let caregiverName: String
    public let attestedAt: Date

    public init(caregiverName: String, attestedAt: Date) {
        self.caregiverName = caregiverName
        self.attestedAt = attestedAt
    }
}

public struct EnrollmentRequest: Sendable {
    public let serverURL: URL
    public let email: String
    public let masterPassword: String
    public let caregiver: CaregiverProfile
    public let pin: String
    public let consent: ConsentRecord

    public init(
        serverURL: URL, email: String, masterPassword: String,
        caregiver: CaregiverProfile, pin: String, consent: ConsentRecord
    ) {
        self.serverURL = serverURL
        self.email = email
        self.masterPassword = masterPassword
        self.caregiver = caregiver
        self.pin = pin
        self.consent = consent
    }
}

/// What the home grid needs — no secrets (§7.4).
public struct MemberTile: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let sortIndex: Int
    public let domain: String?
    public let username: String?
}

/// Detail-screen payload, decrypted on demand.
public struct CredentialSecrets: Equatable, Sendable {
    public let username: String?
    public let password: String?
    public let totp: TOTPGenerator?
}

/// The app-facing vault: enrollment, foreground sync, session unlock, and
/// on-demand decryption. One instance in the app; the autofill extension
/// (M4) builds its own over the same keychain + store.
///
/// Unlock model (§7.3): the first secret-needing call after `lock()` reads
/// the biometry-protected keychain items — the system shows Face ID — and
/// the derived keys stay cached in actor memory until `lock()` (app calls it
/// on backgrounding). There is no lock screen; Face ID *is* the unlock.
/// The single biometry-gated blob (D19): every biometry-protected SecItem
/// read prompts Face ID separately, so all key material shares one item.
struct VaultKeyMaterial: Codable {
    var userKey: Data
    var privateKeyDer: Data
    var organizationKeys: [String: Data]
}

public actor VaultStore {
    private struct SessionKeys {
        let userKey: SymmetricCryptoKey
        let privateKeyDer: Data
        var organizationKeys: [String: SymmetricCryptoKey]
    }

    private let keychain: KeychainStore
    private let cipherStore: CipherStore
    private let transport: any HTTPTransport
    private var client: VaultwardenClient?
    private var sessionKeys: SessionKeys?

    public init(
        keychain: KeychainStore,
        cipherStore: CipherStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.keychain = keychain
        self.cipherStore = cipherStore
        self.transport = transport
    }

    // MARK: Enrollment

    public func isEnrolled() -> Bool {
        passcodeItem(.refreshToken) != nil && passcodeItem(.serverURL) != nil
    }

    /// §7.2 steps 2–3: prelogin → derive → login → sync → full unlock →
    /// persist. All-or-nothing: any failure purges partial state. The master
    /// password lives only in this call's frame and is never stored.
    public func enroll(_ request: EnrollmentRequest) async throws {
        do {
            let deviceIdentifier = UUID()
            let client = makeClient(baseURL: request.serverURL, deviceIdentifier: deviceIdentifier)
            let email = request.email.lowercased()
            let prelogin = try await client.prelogin(email: email)
            let masterKey = try MasterKey.derive(
                password: request.masterPassword, email: email, kdfIterations: prelogin.kdfIterations
            )
            let hash = try MasterKey.authenticationHash(masterKey: masterKey, password: request.masterPassword)
            let token = try await client.login(email: email, masterPasswordHash: hash)
            guard let protectedUserKey = token.key, let encryptedPrivateKey = token.privateKey else {
                throw VaultStoreError.incompleteServerData("password grant returned no protected keys")
            }
            let sync = try await client.sync()
            let keys = try AccountUnlock.unlock(
                email: email,
                password: request.masterPassword,
                kdfIterations: prelogin.kdfIterations,
                protectedUserKey: protectedUserKey,
                encryptedPrivateKey: encryptedPrivateKey
            )
            let privateKeyDer = try encryptedPrivateKey.decrypt(with: keys.userKey)
            var organizationKeys: [String: Data] = [:]
            for organization in sync.profile.organizations {
                guard let encKey = organization.key else { continue }
                organizationKeys[organization.id] = try keys.organizationKey(from: encKey).keyData
            }

            let material = VaultKeyMaterial(
                userKey: keys.userKey.keyData,
                privateKeyDer: privateKeyDer,
                organizationKeys: organizationKeys
            )
            try keychain.store(JSONEncoder().encode(material), for: .vaultKeys)
            try keychain.store(Data(request.serverURL.absoluteString.utf8), for: .serverURL)
            try keychain.store(Data(email.utf8), for: .email)
            try keychain.store(Data(deviceIdentifier.uuidString.lowercased().utf8), for: .deviceIdentifier)
            try keychain.store(JSONEncoder().encode(request.caregiver), for: .caregiverProfile)
            try keychain.store(PINHash.create(request.pin), for: .caregiverPIN)
            try keychain.store(JSONEncoder().encode(request.consent), for: .consentRecord)
            try saveSnapshot(from: sync)
            self.client = client
        } catch {
            reset()
            throw error
        }
    }

    /// Purge all secrets and sync state — enrollment reset and the
    /// reenroll-required path (§6.3). The caregiver's contact card, the
    /// consent record, and the caregiver PIN survive: after a purge the only
    /// screen left is call-caregiver, and it needs the phone number
    /// (principle 4) plus a working hidden door so the caregiver can
    /// re-enroll without reinstalling (D19).
    public func reset() {
        keychain.purgeEverything(except: [.caregiverProfile, .consentRecord, .caregiverPIN])
        cipherStore.wipe()
        sessionKeys = nil
        client = nil
    }

    // MARK: Sync

    /// Foreground/refresh sync. `.reenrollRequired` purges local state
    /// before rethrowing; transient failures (`offline`/`serverUnavailable`)
    /// pass through untouched — the member keeps working from the snapshot.
    @discardableResult
    public func syncNow() async throws -> VaultSnapshot {
        let client = try activeClient()
        do {
            return try saveSnapshot(from: try await client.sync())
        } catch AmparoError.reenrollRequired {
            reset()
            throw AmparoError.reenrollRequired
        }
    }

    public func lastSnapshot() throws -> VaultSnapshot? {
        try cipherStore.load()
    }

    /// Icon bytes for a tile (nil → monogram fallback). Failures are never
    /// member-visible; pair with `IconCache` at the call site.
    public func fetchIconData(domain: String) async -> Data? {
        guard let client = try? activeClient() else { return nil }
        return (try? await client.fetchIcon(domain: domain)) ?? nil
    }

    // MARK: Member reads

    /// Drop cached keys; next secret access re-triggers Face ID. Call on
    /// scene-background.
    public func lock() {
        sessionKeys = nil
    }

    public func tiles() throws -> [MemberTile] {
        _ = try ensureUnlocked()
        guard let snapshot = try cipherStore.load() else { return [] }
        var tiles: [MemberTile] = []
        for cipher in snapshot.ciphers {
            guard let key = decryptionKey(for: cipher, snapshot: snapshot),
                  let rawName = try? cipher.name?.decryptString(with: key) else { continue }
            let (sortIndex, displayName) = CipherPresentation.split(rawName)
            tiles.append(MemberTile(
                id: cipher.id,
                displayName: displayName,
                sortIndex: sortIndex,
                domain: (try? cipher.login?.uris?.first?.uri?.decryptString(with: key))
                    .flatMap(CipherPresentation.domain(fromURI:)),
                username: try? cipher.login?.username?.decryptString(with: key)
            ))
        }
        return tiles.sorted {
            ($0.sortIndex, $0.displayName) < ($1.sortIndex, $1.displayName)
        }
    }

    public func secrets(forCipher id: String) throws -> CredentialSecrets? {
        _ = try ensureUnlocked()
        guard let snapshot = try cipherStore.load(),
              let cipher = snapshot.ciphers.first(where: { $0.id == id }),
              let key = decryptionKey(for: cipher, snapshot: snapshot)
        else { return nil }
        return CredentialSecrets(
            username: try? cipher.login?.username?.decryptString(with: key),
            password: try? cipher.login?.password?.decryptString(with: key),
            totp: (try? cipher.login?.totp?.decryptString(with: key)).flatMap(TOTPGenerator.init(field:))
        )
    }

    // MARK: Caregiver-facing state

    public func caregiverProfile() -> CaregiverProfile? {
        passcodeItem(.caregiverProfile).flatMap { try? JSONDecoder().decode(CaregiverProfile.self, from: $0) }
    }

    public func serverURLString() -> String? {
        passcodeItem(.serverURL).map { String(decoding: $0, as: UTF8.self) }
    }

    public func consentRecord() -> ConsentRecord? {
        passcodeItem(.consentRecord).flatMap { try? JSONDecoder().decode(ConsentRecord.self, from: $0) }
    }

    public func verifyCaregiverPIN(_ pin: String) -> Bool {
        guard let stored = passcodeItem(.caregiverPIN) else { return false }
        return PINHash.verify(pin, against: stored)
    }

    // MARK: Internals

    private func ensureUnlocked() throws -> SessionKeys {
        if let sessionKeys { return sessionKeys }
        guard isEnrolled() else { throw VaultStoreError.notEnrolled }
        // The one biometry-protected read: the system prompts Face ID here,
        // exactly once per unlocked session (D19).
        guard let blob = try keychain.read(.vaultKeys) else {
            throw VaultStoreError.biometryInvalidated
        }
        guard let material = try? JSONDecoder().decode(VaultKeyMaterial.self, from: blob) else {
            throw VaultStoreError.storeCorrupted
        }
        var organizationKeys: [String: SymmetricCryptoKey] = [:]
        for (orgId, raw) in material.organizationKeys {
            guard let key = try? SymmetricCryptoKey(data: raw) else {
                throw VaultStoreError.storeCorrupted
            }
            organizationKeys[orgId] = key
        }
        let keys = SessionKeys(
            userKey: try SymmetricCryptoKey(data: material.userKey),
            privateKeyDer: material.privateKeyDer,
            organizationKeys: organizationKeys
        )
        sessionKeys = keys
        return keys
    }

    /// Key selection per §6.4, with late unwrap for an organization that
    /// appeared after enrollment (the private key is already in the session
    /// material — no extra Face ID). nil = no key path for this cipher —
    /// skip it, never guess.
    private func decryptionKey(for cipher: Cipher, snapshot: VaultSnapshot) -> SymmetricCryptoKey? {
        guard var keys = sessionKeys else { return nil }
        guard let orgId = cipher.organizationId else { return keys.userKey }
        if let known = keys.organizationKeys[orgId] { return known }
        guard let serialized = snapshot.organizationKeyStrings[orgId],
              let encKey = try? EncString(parsing: serialized),
              let privateKey = try? RSAPrivateKey(pkcs8Der: keys.privateKeyDer),
              let unwrapped = try? SymmetricCryptoKey(data: privateKey.decrypt(encKey))
        else { return nil }
        keys.organizationKeys[orgId] = unwrapped
        sessionKeys = keys
        persistSessionMaterial()  // next session skips the RSA unwrap
        return unwrapped
    }

    /// Rebuild and rewrite the biometry blob from the unlocked session
    /// (writes never prompt; only reads are gated).
    private func persistSessionMaterial() {
        guard let keys = sessionKeys else { return }
        let material = VaultKeyMaterial(
            userKey: keys.userKey.keyData,
            privateKeyDer: keys.privateKeyDer,
            organizationKeys: keys.organizationKeys.mapValues(\.keyData)
        )
        if let encoded = try? JSONEncoder().encode(material) {
            try? keychain.store(encoded, for: .vaultKeys)
        }
    }

    @discardableResult
    private func saveSnapshot(from sync: SyncResponse) throws -> VaultSnapshot {
        var organizationKeyStrings: [String: String] = [:]
        for organization in sync.profile.organizations {
            if let key = organization.key {
                organizationKeyStrings[organization.id] = key.serialized()
            }
        }
        let snapshot = VaultSnapshot(
            syncedAt: Date(),
            organizationKeyStrings: organizationKeyStrings,
            ciphers: sync.loginCiphers
        )
        try cipherStore.save(snapshot)
        return snapshot
    }

    private func activeClient() throws -> VaultwardenClient {
        if let client { return client }
        guard
            let urlData = passcodeItem(.serverURL),
            let baseURL = URL(string: String(decoding: urlData, as: UTF8.self)),
            let deviceData = passcodeItem(.deviceIdentifier),
            let deviceIdentifier = UUID(uuidString: String(decoding: deviceData, as: UTF8.self)),
            let tokenData = passcodeItem(.refreshToken)
        else { throw VaultStoreError.notEnrolled }
        let restored = makeClient(
            baseURL: baseURL,
            deviceIdentifier: deviceIdentifier,
            refreshToken: String(decoding: tokenData, as: UTF8.self)
        )
        client = restored
        return restored
    }

    private func makeClient(
        baseURL: URL, deviceIdentifier: UUID, refreshToken: String? = nil
    ) -> VaultwardenClient {
        let keychain = keychain
        return VaultwardenClient(
            baseURL: baseURL,
            deviceIdentifier: deviceIdentifier,
            transport: transport,
            refreshToken: refreshToken,
            onTokensUpdated: { pair in
                try? keychain.store(Data(pair.refreshToken.utf8), for: .refreshToken)
            }
        )
    }

    private func passcodeItem(_ item: KeychainItem) -> Data? {
        (try? keychain.read(item)) ?? nil
    }
}

/// D4 ordering convention: `1. Banco` → sort 1, display "Banco". Names
/// without the prefix sort last, alphabetically.
enum CipherPresentation {
    static func split(_ raw: String) -> (sortIndex: Int, displayName: String) {
        guard let match = raw.firstMatch(of: /^(\d+)\.\s*(\S.*)$/),
              let index = Int(match.1) else {
            return (Int.max, raw)
        }
        return (index, String(match.2))
    }

    static func domain(fromURI uri: String) -> String? {
        if let host = URL(string: uri)?.host { return host }
        // bw accepts bare hostnames as URIs.
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("/") ? nil : trimmed
    }
}

/// Caregiver PIN at rest: salt ‖ SHA-256(salt ‖ UTF8(pin)). A local
/// convenience gate for the hidden settings, not a cryptographic boundary —
/// the real secrets are behind biometry.
enum PINHash {
    static func create(_ pin: String) -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return salt + digest(salt: salt, pin: pin)
    }

    static func verify(_ pin: String, against stored: Data) -> Bool {
        guard stored.count == 16 + 32 else { return false }
        let salt = stored.prefix(16)
        return Data(stored.suffix(32)) == digest(salt: Data(salt), pin: pin)
    }

    private static func digest(salt: Data, pin: String) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}
