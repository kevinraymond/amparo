import Foundation
import Testing
@testable import AmparoAPI

@Suite("Prelogin")
struct PreloginTests {
    @Test func decodesCapturedResponse() async throws {
        let (status, body) = try Samples.load("prelogin")
        let transport = StubTransport([.response(status: status, body: body)])
        let client = VaultwardenClient.test(transport: transport)

        let response = try await client.prelogin(email: "Member@Amparo.Test")

        #expect(response == PreloginResponse(kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil))
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url == "https://vw.test:8443/identity/accounts/prelogin")
        #expect(request.headers["Content-Type"] == "application/json")
        let sent = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(sent == ["email": "member@amparo.test"])
    }

    @Test func argon2AccountIsUnsupportedKdf() async throws {
        // Synthetic: the runbook pins member accounts to PBKDF2 (D3), so a
        // kdf=1 answer means a misconfigured account, not a code path.
        let body = Data(#"{"kdf": 1, "kdfIterations": 3, "kdfMemory": 64, "kdfParallelism": 4}"#.utf8)
        let transport = StubTransport([.response(status: 200, body: body)])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.unsupportedKdf(kdf: 1)) {
            try await client.prelogin(email: "member@amparo.test")
        }
    }
}
