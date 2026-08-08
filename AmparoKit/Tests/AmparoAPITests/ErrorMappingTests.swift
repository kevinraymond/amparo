import Foundation
import Testing
@testable import AmparoAPI

@Suite("Error mapping")
struct ErrorMappingTests {
    @Test func transportFailureIsOffline() async throws {
        let transport = StubTransport([.failure(URLError(.notConnectedToInternet))])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.offline(.notConnectedToInternet)) {
            try await client.login(email: "member@amparo.test", masterPasswordHash: "x")
        }
    }

    @Test(arguments: [500, 502, 503, 429])
    func serverErrorsAreServerUnavailable(status: Int) async throws {
        let transport = StubTransport([.response(status: status, body: Data())])
        let client = VaultwardenClient.test(transport: transport)

        await #expect(throws: AmparoError.serverUnavailable(status: status)) {
            try await client.login(email: "member@amparo.test", masterPasswordHash: "x")
        }
    }

    @Test func undecodableSuccessBodyIsUnexpectedResponse() async throws {
        let transport = StubTransport([.response(status: 200, body: Data("not json".utf8))])
        let client = VaultwardenClient.test(transport: transport)

        do {
            try await client.login(email: "member@amparo.test", masterPasswordHash: "x")
            Issue.record("expected login to throw")
        } catch let error as AmparoError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected .unexpectedResponse, got \(error)")
                return
            }
        }
    }

    @Test func unclassifiablePreloginStatusIsUnexpectedResponse() async throws {
        let transport = StubTransport([.response(status: 404, body: Data())])
        let client = VaultwardenClient.test(transport: transport)

        do {
            _ = try await client.prelogin(email: "member@amparo.test")
            Issue.record("expected prelogin to throw")
        } catch let error as AmparoError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected .unexpectedResponse, got \(error)")
                return
            }
        }
    }
}
