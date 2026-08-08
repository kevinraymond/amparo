import Foundation
@testable import AmparoAPI
@testable import AmparoShared

/// Minimal scripted transport (same shape as AmparoAPITests'; SPM test
/// targets can't share code).
actor StubTransport: HTTPTransport {
    enum Scripted {
        case response(status: Int, body: Data)
        case failure(URLError)
    }

    private var script: [Scripted]
    private(set) var requestURLs: [String] = []

    init(_ script: [Scripted]) {
        self.script = script
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestURLs.append(request.url?.absoluteString ?? "")
        guard !script.isEmpty else { throw URLError(.unknown) }
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

/// Loads captured samples from the sibling test target's resources by
/// source-relative path — one committed copy of the fixture data, consumed
/// by both targets. Valid wherever `swift test` runs from a checkout.
enum SharedSamples {
    static func load(_ name: String) throws -> (status: Int, body: Data) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AmparoAPITests/Resources/\(name).json")
        let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let body = try JSONSerialization.data(withJSONObject: envelope["body"]!)
        return (envelope["status"] as! Int, body)
    }

    /// The M1 E2E vectors, for cross-checking enrollment's derived keys.
    static func vectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AmparoCryptoTests/Resources/e2e-vectors.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
}

/// A fully wired VaultStore over fakes: in-memory keychain (no biometry in
/// tests — reads always succeed), temp-file cipher store, scripted network.
struct TestVault {
    let vault: VaultStore
    let keychain: KeychainStore
    let fakeSecItems: FakeSecItemClient
    let cipherStore: CipherStore
    let transport: StubTransport

    init(script: [StubTransport.Scripted]) {
        let fake = FakeSecItemClient()
        let keychain = KeychainStore(
            configuration: .init(service: "test.amparo", accessGroup: nil), client: fake
        )
        let cipherStore = CipherStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("amparo-tests-\(UUID().uuidString).json")
        )
        let transport = StubTransport(script)
        self.vault = VaultStore(keychain: keychain, cipherStore: cipherStore, transport: transport)
        self.keychain = keychain
        self.fakeSecItems = fake
        self.cipherStore = cipherStore
        self.transport = transport
    }

    static func enrollmentRequest(pin: String = "2468") -> EnrollmentRequest {
        EnrollmentRequest(
            serverURL: URL(string: "https://vw.test:8443")!,
            email: "member@amparo.test",
            masterPassword: "Fixture-Member-2026-Hx7q",
            caregiver: CaregiverProfile(name: "Dev Caregiver", phone: "+15551234567"),
            pin: pin,
            consent: ConsentRecord(
                caregiverName: "Dev Caregiver",
                attestedAt: Date(timeIntervalSince1970: 1_754_000_000)
            )
        )
    }

    /// prelogin + password grant + sync — the happy enrollment script.
    static func happyEnrollmentScript() throws -> [StubTransport.Scripted] {
        let prelogin = try SharedSamples.load("prelogin")
        let token = try SharedSamples.load("token-success")
        let sync = try SharedSamples.load("sync-success")
        return [
            .response(status: prelogin.status, body: prelogin.body),
            .response(status: token.status, body: token.body),
            .response(status: sync.status, body: sync.body),
        ]
    }
}
