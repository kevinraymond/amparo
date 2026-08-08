import Foundation
import Testing
@testable import AmparoAPI

@Suite("Token endpoint")
struct TokenEndpointTests {
    @Test func loginSendsExactFormBodyAndHeaders() async throws {
        let (status, body) = try Samples.load("token-success")
        let transport = StubTransport([.response(status: status, body: body)])
        let client = VaultwardenClient.test(transport: transport)

        // Mixed-case email must be lowercased; hash exercises +/= escaping.
        try await client.login(email: "Member@Amparo.Test", masterPasswordHash: "abc+/=XYZ")

        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url == "https://vw.test:8443/identity/connect/token")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        // Unpadded base64url of "member@amparo.test" (Node b64url semantics).
        #expect(request.headers["Auth-Email"] == "bWVtYmVyQGFtcGFyby50ZXN0")
        let bodyString = String(data: try #require(request.body), encoding: .utf8)
        #expect(bodyString == "grant_type=password&scope=api+offline_access&client_id=mobile"
            + "&username=member%40amparo.test&password=abc%2B%2F%3DXYZ"
            + "&deviceType=1&deviceIdentifier=d5c1c8a0-6e5b-4e62-9f5a-1b2c3d4e5f60"
            + "&deviceName=amparo-ios")
    }

    @Test func loginDecodesCapturedResponseAndEmitsTokens() async throws {
        let (status, body) = try Samples.load("token-success")
        let transport = StubTransport([.response(status: status, body: body)])
        let log = TokenLog()
        let client = VaultwardenClient.test(transport: transport, onTokensUpdated: log.append)

        let response = try await client.login(email: "member@amparo.test", masterPasswordHash: "x")

        #expect(response.key != nil)
        #expect(response.privateKey != nil)
        #expect(response.key?.type == 2)
        #expect(response.kdf == 0)
        #expect(response.kdfIterations == 600_000)
        #expect(log.all.count == 1)
        #expect(log.all.first?.accessToken == response.accessToken)
        #expect(log.all.first?.refreshToken == response.refreshToken)
    }

    @Test func refreshSendsExactFormBodyWithoutAuthEmail() async throws {
        let (status, body) = try Samples.load("token-success")
        let transport = StubTransport([.response(status: status, body: body)])
        let log = TokenLog()
        let client = VaultwardenClient.test(
            transport: transport, refreshToken: "rt-1", onTokensUpdated: log.append
        )

        try await client.refresh()

        let request = try #require(await transport.requests.first)
        #expect(request.headers["Auth-Email"] == nil)
        let bodyString = String(data: try #require(request.body), encoding: .utf8)
        #expect(bodyString == "grant_type=refresh_token&client_id=mobile&refresh_token=rt-1")
        #expect(log.all.count == 1)
    }

    @Test func capturedWrongPasswordBodyMapsToInvalidCredentials() async throws {
        let (status, body) = try Samples.load("token-wrong-password")
        let transport = StubTransport([.response(status: status, body: body)])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.invalidCredentials) {
            try await client.login(email: "member@amparo.test", masterPasswordHash: "wrong")
        }
    }

    @Test func capturedTwoFactorChallengeMapsToTwoFactorRequired() async throws {
        // The captured body also carries error=invalid_grant — this test
        // pins that the 2FA probe wins over the credentials classification.
        let (status, body) = try Samples.load("token-2fa")
        let transport = StubTransport([.response(status: status, body: body)])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.twoFactorRequired) {
            try await client.login(email: "twofa-sample@amparo.test", masterPasswordHash: "x")
        }
    }

    @Test func capturedInvalidRefreshBodyMapsToReenrollRequired() async throws {
        let (status, body) = try Samples.load("token-refresh-invalid")
        let transport = StubTransport([.response(status: status, body: body)])
        let client = VaultwardenClient.test(transport: transport, refreshToken: "revoked")

        await #expect(throws: AmparoError.reenrollRequired) {
            try await client.refresh()
        }
    }

    @Test func refreshWithoutTokenIsReenrollRequiredWithoutNetworkTraffic() async throws {
        let transport = StubTransport([])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.reenrollRequired) {
            try await client.refresh()
        }
        #expect(await transport.requests.isEmpty)
    }
}
