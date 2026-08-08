import Foundation
import Testing
@testable import AmparoAPI

@Suite("Icons")
struct IconTests {
    @Test func fetchesIconBytesWithoutAuth() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let transport = StubTransport([.response(status: 200, body: png)])
        let client = VaultwardenClient.test(transport: transport)

        let icon = try await client.fetchIcon(domain: "banco.example.com")

        #expect(icon == png)
        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://vw.test:8443/icons/banco.example.com/icon.png")
        #expect(request.headers["Authorization"] == nil)
    }

    @Test func missingIconIsNilNotAnError() async throws {
        let transport = StubTransport([.response(status: 404, body: Data())])
        let client = VaultwardenClient.test(transport: transport)

        #expect(try await client.fetchIcon(domain: "unknown.example.com") == nil)
    }
}
