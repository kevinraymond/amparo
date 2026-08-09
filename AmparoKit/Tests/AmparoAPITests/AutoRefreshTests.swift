import Foundation
import Testing
@testable import AmparoAPI

@Suite("Sync auto-refresh")
struct AutoRefreshTests {
    private func loginThenSync(script: [StubTransport.Scripted]) async throws -> (VaultwardenClient, StubTransport) {
        let token = try Samples.load("token-success")
        let transport = StubTransport([.response(status: token.status, body: token.body)] + script)
        let client = VaultwardenClient.test(transport: transport)
        try await client.login(email: "member@amparo.test", masterPasswordHash: "x")
        return (client, transport)
    }

    @Test func retriesExactlyOnceAfter401() async throws {
        let token = try Samples.load("token-success")
        let sync = try Samples.load("sync-success")
        let (client, transport) = try await loginThenSync(script: [
            .response(status: 401, body: Data()),
            .response(status: token.status, body: token.body),
            .response(status: sync.status, body: sync.body),
        ])

        let response = try await client.sync()

        #expect(response.ciphers.count == 11)
        let urls = await transport.requests.map(\.url)
        #expect(urls == [
            "https://vw.test:8443/identity/connect/token",
            "https://vw.test:8443/api/sync?excludeDomains=true",
            "https://vw.test:8443/identity/connect/token",
            "https://vw.test:8443/api/sync?excludeDomains=true",
        ])
    }

    @Test func secondUnauthorizedIsReenrollRequired() async throws {
        let token = try Samples.load("token-success")
        let (client, _) = try await loginThenSync(script: [
            .response(status: 401, body: Data()),
            .response(status: token.status, body: token.body),
            .response(status: 401, body: Data()),
        ])

        await #expect(throws: AmparoError.reenrollRequired) {
            try await client.sync()
        }
    }

    @Test func refreshRejectionDuringSyncIsReenrollRequired() async throws {
        let invalid = try Samples.load("token-refresh-invalid")
        let (client, _) = try await loginThenSync(script: [
            .response(status: 401, body: Data()),
            .response(status: invalid.status, body: invalid.body),
        ])

        await #expect(throws: AmparoError.reenrollRequired) {
            try await client.sync()
        }
    }

    /// The safety rule behind handoff principle 5: a network failure during
    /// refresh must never masquerade as revocation — offline members keep
    /// their local vault.
    @Test func offlineDuringRefreshIsOfflineNotReenroll() async throws {
        let (client, _) = try await loginThenSync(script: [
            .response(status: 401, body: Data()),
            .failure(URLError(.notConnectedToInternet)),
        ])

        await #expect(throws: AmparoError.offline(.notConnectedToInternet)) {
            try await client.sync()
        }
    }

    @Test func syncWithNoTokensIsReenrollRequiredWithoutNetworkTraffic() async throws {
        let transport = StubTransport([])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.reenrollRequired) {
            try await client.sync()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func concurrentSyncsShareOneRefresh() async throws {
        let token = try Samples.load("token-success")
        let sync = try Samples.load("sync-success")
        let transport = StubTransport([
            .response(status: token.status, body: token.body),
            .response(status: sync.status, body: sync.body),
            .response(status: sync.status, body: sync.body),
        ])
        let client = VaultwardenClient.test(transport: transport, refreshToken: "rt-1")

        async let first = client.sync()
        async let second = client.sync()
        _ = try await (first, second)

        let urls = await transport.requests.map(\.url)
        #expect(urls.count(where: { $0 == "https://vw.test:8443/identity/connect/token" }) == 1)
        #expect(urls.count(where: { $0 == "https://vw.test:8443/api/sync?excludeDomains=true" }) == 2)
    }
}
