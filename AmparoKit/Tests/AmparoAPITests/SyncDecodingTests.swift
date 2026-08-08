import Foundation
import Testing
@testable import AmparoAPI

@Suite("Sync decoding")
struct SyncDecodingTests {
    /// The captured dev-server payload: 9 org ciphers + 1 personal, exactly
    /// one with TOTP (fixtures/README.md).
    @Test func decodesCapturedSyncPayload() async throws {
        let token = try Samples.load("token-success")
        let sync = try Samples.load("sync-success")
        let transport = StubTransport([
            .response(status: token.status, body: token.body),
            .response(status: sync.status, body: sync.body),
        ])
        let client = VaultwardenClient.test(transport: transport, refreshToken: "rt-1")

        let response = try await client.sync()

        #expect(response.ciphers.count == 10)
        #expect(response.loginCiphers.count == 10)
        #expect(response.profile.key.type == 2)
        #expect(response.profile.privateKey.type == 2)
        #expect(response.profile.organizations.count == 1)
        #expect(response.profile.organizations.first?.key?.type == 4)
        #expect(response.ciphers.filter { $0.organizationId == nil }.count == 1)
        #expect(response.ciphers.filter { $0.login?.totp != nil }.count == 1)
        #expect(response.ciphers.allSatisfy { $0.login?.uris?.first?.uri != nil })

        // No-access-token start: refresh first, then sync with its bearer.
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url == "https://vw.test:8443/identity/connect/token")
        #expect(requests[1].url == "https://vw.test:8443/api/sync?excludeDomains=true")
        #expect(requests[1].headers["Authorization"]?.hasPrefix("Bearer ") == true)
    }

    @Test func toleratesCasingNullsUnknownsAndBadElements() async throws {
        let token = try Samples.load("token-success")
        let tolerant = try Samples.load("sync-tolerant")
        let transport = StubTransport([
            .response(status: token.status, body: token.body),
            .response(status: tolerant.status, body: tolerant.body),
        ])
        let client = VaultwardenClient.test(transport: transport, refreshToken: "rt-1")

        let response = try await client.sync()

        // The undecodable element (numeric Id) is dropped; everything else
        // survives, including the non-Login and trashed ciphers.
        #expect(response.ciphers.map(\.id) == ["c-login", "c-note", "c-trashed"])
        // …but only live Login ciphers are consumable (§6.4).
        #expect(response.loginCiphers.map(\.id) == ["c-login"])
        #expect(response.profile.email == nil)
        #expect(response.profile.organizations.first?.key?.type == 4)
        let login = try #require(response.loginCiphers.first?.login)
        #expect(login.username != nil)
        #expect(login.password == nil)
        #expect(login.uris?.first?.uri != nil)
    }

    @Test func syncWithUnusableProfileIsUnexpectedResponse() async throws {
        // Missing profile keys means the account cannot be unlocked — that
        // must be a loud, typed failure, not a silent partial sync.
        let token = try Samples.load("token-success")
        let body = Data(#"{"profile": {"id": "p"}, "ciphers": []}"#.utf8)
        let transport = StubTransport([
            .response(status: token.status, body: token.body),
            .response(status: 200, body: body),
        ])
        let client = VaultwardenClient.test(transport: transport, refreshToken: "rt-1")

        do {
            _ = try await client.sync()
            Issue.record("expected sync to throw")
        } catch let error as AmparoError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected .unexpectedResponse, got \(error)")
                return
            }
        }
    }
}
