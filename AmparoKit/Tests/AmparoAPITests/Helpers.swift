import Foundation
@testable import AmparoAPI

/// Replays scripted responses in order and records what was sent. A test
/// declares the whole conversation up front; running out of script is a
/// test bug and fails loudly.
actor StubTransport: HTTPTransport {
    enum Scripted {
        case response(status: Int, body: Data)
        case failure(URLError)
    }

    struct Recorded: Sendable {
        let method: String?
        let url: String?
        let headers: [String: String]
        let body: Data?
    }

    private var script: [Scripted]
    private(set) var requests: [Recorded] = []

    init(_ script: [Scripted]) {
        self.script = script
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(Recorded(
            method: request.httpMethod,
            url: request.url?.absoluteString,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        ))
        guard !script.isEmpty else {
            throw URLError(.unknown) // script exhausted — test declared too few responses
        }
        switch script.removeFirst() {
        case .response(let status, let body):
            let http = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (body, http)
        case .failure(let error):
            throw error
        }
    }
}

/// Loads a captured sample (fixtures/capture-samples.mjs envelope) and
/// returns the original status plus the raw body bytes.
enum Samples {
    static func load(_ name: String) throws -> (status: Int, body: Data) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let body = try JSONSerialization.data(withJSONObject: envelope["body"]!)
        return (envelope["status"] as! Int, body)
    }
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

extension VaultwardenClient {
    /// Every test client uses the same stable identity so request assertions
    /// can be exact.
    static func test(
        transport: StubTransport,
        refreshToken: String? = nil,
        onTokensUpdated: (@Sendable (TokenPair) -> Void)? = nil
    ) -> VaultwardenClient {
        VaultwardenClient(
            baseURL: URL(string: "https://vw.test:8443")!,
            deviceIdentifier: UUID(uuidString: "D5C1C8A0-6E5B-4E62-9F5A-1B2C3D4E5F60")!,
            transport: transport,
            refreshToken: refreshToken,
            onTokensUpdated: onTokensUpdated
        )
    }
}
