import AmparoCrypto
import Foundation
import Testing
@testable import AmparoAPI

/// Live tests against the dev Vaultwarden (handoff §5, M2-T3). Skipped
/// unless `AMPARO_VW_URL` is set; run with:
///
///     set -a; source fixtures/fixtures.env; set +a
///     cd AmparoKit && swift test --filter AmparoAPIIntegrationTests
///
/// `.serialized` keeps token-endpoint traffic sequential (Vaultwarden
/// rate-limits logins).
@Suite(.serialized, .enabled(if: Env.baseURL != nil, "AMPARO_VW_URL not set — see fixtures/README.md"))
struct IntegrationTests {
    /// Fixture vault content (fixtures/seed.sh).
    private static let allCipherNames = [
        "1. Banco", "2. Email", "3. Plano de Saude", "4. Farmacia", "5. Mercado",
        "6. Streaming", "7. Telefone", "8. Luz", "9. Previdencia", "Portal Medico",
    ]

    private func makeClient(
        refreshToken: String? = nil,
        onTokensUpdated: (@Sendable (TokenPair) -> Void)? = nil
    ) -> VaultwardenClient {
        VaultwardenClient(
            baseURL: Env.baseURL!,
            deviceIdentifier: Env.deviceIdentifier,
            refreshToken: refreshToken,
            onTokensUpdated: onTokensUpdated
        )
    }

    /// prelogin → derive (AmparoCrypto) → password grant.
    private func login(
        _ client: VaultwardenClient
    ) async throws -> (token: TokenResponse, kdfIterations: Int) {
        let pre = try await client.prelogin(email: Env.memberEmail)
        let masterKey = try MasterKey.derive(
            password: Env.memberPassword, email: Env.memberEmail, kdfIterations: pre.kdfIterations
        )
        let hash = try MasterKey.authenticationHash(masterKey: masterKey, password: Env.memberPassword)
        let token = try await client.login(email: Env.memberEmail, masterPasswordHash: hash)
        return (token, pre.kdfIterations)
    }

    @Test func preloginReportsPinnedPBKDF2() async throws {
        let pre = try await makeClient().prelogin(email: Env.memberEmail)
        #expect(pre.kdf == 0)
        #expect(pre.kdfIterations == 600_000)
    }

    @Test func loginHappyPathDeliversTokensAndProtectedKeys() async throws {
        let (token, _) = try await login(makeClient())
        #expect(!token.accessToken.isEmpty)
        #expect(token.refreshToken?.isEmpty == false)
        #expect(token.key?.type == 2)
        #expect(token.privateKey?.type == 2)
    }

    @Test func wrongPasswordIsInvalidCredentials() async throws {
        let client = makeClient()
        await #expect(throws: AmparoError.invalidCredentials) {
            try await client.login(email: Env.memberEmail, masterPasswordHash: "d3Jvbmc=")
        }
    }

    @Test func refreshedSessionSyncsAndEmitsTokenUpdates() async throws {
        let log = TokenLog()
        let client = makeClient(onTokensUpdated: log.append)
        _ = try await login(client)
        let pair = try await client.refresh()
        #expect(!pair.accessToken.isEmpty)
        let sync = try await client.sync()
        #expect(!sync.ciphers.isEmpty)
        // One emission per grant; rotation is the server's choice, observed
        // behaviorally rather than asserted.
        #expect(log.all.count == 2)
    }

    /// The M2 exit criterion: a live sync decrypts the entire fixture vault
    /// through the real key chain — user key for the personal cipher, org
    /// key for the collection — with plaintext names matching seed.sh.
    @Test func syncDecryptsEveryFixtureCipher() async throws {
        let client = makeClient()
        let (token, kdfIterations) = try await login(client)
        let sync = try await client.sync()

        let keys = try AccountUnlock.unlock(
            email: Env.memberEmail,
            password: Env.memberPassword,
            kdfIterations: kdfIterations,
            protectedUserKey: try #require(token.key),
            encryptedPrivateKey: try #require(token.privateKey)
        )
        var orgKeys: [String: SymmetricCryptoKey] = [:]
        for org in sync.profile.organizations {
            orgKeys[org.id] = try keys.organizationKey(from: try #require(org.key))
        }

        var names: [String] = []
        var totpCount = 0
        for cipher in sync.loginCiphers {
            let key = try cipher.organizationId.map { try #require(orgKeys[$0]) } ?? keys.userKey
            names.append(try #require(cipher.name).decryptString(with: key))
            let loginData = try #require(cipher.login)
            #expect(!(try #require(loginData.username).decryptString(with: key)).isEmpty)
            #expect(!(try #require(loginData.password).decryptString(with: key)).isEmpty)
            #expect(!(try #require(loginData.uris?.first?.uri).decryptString(with: key)).isEmpty)
            if let totp = loginData.totp {
                totpCount += 1
                #expect(!(try totp.decryptString(with: key)).isEmpty)
            }
        }
        #expect(names.sorted() == Self.allCipherNames.sorted())
        #expect(totpCount == 1)
        let personal = sync.loginCiphers.filter { $0.organizationId == nil }
        #expect(personal.count == 1)
        #expect(try personal.first?.name?.decryptString(with: keys.userKey) == "Portal Medico")
    }

    /// The agreed revoked-token strategy (D15): the server's definitive
    /// `invalid_grant` on refresh maps to the typed purge signal.
    @Test func garbageRefreshTokenIsReenrollRequired() async throws {
        let client = makeClient(refreshToken: "garbage-refresh-token")
        await #expect(throws: AmparoError.reenrollRequired) {
            _ = try await client.sync()
        }
    }

    @Test func iconEndpointIsReachableWithoutAuth() async throws {
        // The dev server can't resolve real favicons for fixture domains;
        // bytes and nil are both valid observed answers. The assertion is
        // that the unauthenticated endpoint answers without a typed failure.
        _ = try await makeClient().fetchIcon(domain: "example.com")
    }
}

enum Env {
    static let baseURL = ProcessInfo.processInfo.environment["AMPARO_VW_URL"].flatMap(URL.init(string:))
    static let memberEmail = ProcessInfo.processInfo.environment["MEMBER_EMAIL"] ?? "member@amparo.test"
    static let memberPassword = ProcessInfo.processInfo.environment["MEMBER_PASSWORD"] ?? "Fixture-Member-2026-Hx7q"
    /// Stable so integration runs don't accumulate device rows server-side
    /// (same idea as the fixtures' per-email derivation).
    static let deviceIdentifier = UUID(uuidString: "a2f1c8d0-3b4e-4a5f-8c6d-7e8f9a0b1c2d")!
}

/// Collects `onTokensUpdated` emissions from any isolation context.
final class TokenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var pairs: [TokenPair] = []

    func append(_ pair: TokenPair) {
        lock.withLock { pairs.append(pair) }
    }

    var all: [TokenPair] {
        lock.withLock { pairs }
    }
}
