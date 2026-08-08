import AmparoCrypto
import Foundation

/// Vaultwarden protocol client (§6.3–§6.5): prelogin, ROPC login, token
/// refresh, sync, icons. One instance per account; the app and the autofill
/// extension each construct their own.
///
/// Token custody (D12): both tokens live only in actor memory. Every
/// successful login/refresh emits the pair through `onTokensUpdated`; the
/// caller owns durability (M3 Keychain) and seeds `refreshToken` back in at
/// init. The access token is never persisted — a fresh process refreshes on
/// first `sync()`.
public actor VaultwardenClient {
    private let baseURL: URL
    private let deviceIdentifier: String
    private let transport: any HTTPTransport
    private let onTokensUpdated: (@Sendable (TokenPair) -> Void)?
    private let decoder = JSONDecoder.vaultwarden()

    private var accessToken: String?
    private var refreshToken: String?
    private var refreshTask: Task<TokenPair, Error>?

    public init(
        baseURL: URL,
        deviceIdentifier: UUID,
        transport: any HTTPTransport = URLSessionTransport(),
        refreshToken: String? = nil,
        onTokensUpdated: (@Sendable (TokenPair) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.deviceIdentifier = deviceIdentifier.uuidString.lowercased()
        self.transport = transport
        self.refreshToken = refreshToken
        self.onTokensUpdated = onTokensUpdated
    }

    // MARK: Endpoints

    /// `POST /identity/accounts/prelogin`. Throws `.unsupportedKdf` for
    /// anything but PBKDF2 — the app has no Argon2id path (D3), so a non-zero
    /// kdf can never reach the derivation code.
    public func prelogin(email: String) async throws -> PreloginResponse {
        var request = makeRequest("POST", "/identity/accounts/prelogin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email.lowercased()])
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else {
            throw AmparoError.unexpectedResponse("prelogin HTTP \(http.statusCode)")
        }
        let response: PreloginResponse = try decode(data, context: "prelogin")
        guard response.kdf == 0 else { throw AmparoError.unsupportedKdf(kdf: response.kdf) }
        return response
    }

    /// §6.3 password grant. `masterPasswordHash` comes from
    /// `MasterKey.derive` + `MasterKey.authenticationHash`; the master
    /// password itself never reaches this layer.
    @discardableResult
    public func login(email: String, masterPasswordHash: String) async throws -> TokenResponse {
        let email = email.lowercased()
        var request = makeRequest("POST", "/identity/connect/token")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Auth-Email accompanies only requests that carry `username`
        // (behavioral: register-helper.mjs); base64url is unpadded.
        request.setValue(Self.base64url(email), forHTTPHeaderField: "Auth-Email")
        request.httpBody = Data(Self.formEncode([
            ("grant_type", "password"),
            ("scope", "api offline_access"),
            ("client_id", "mobile"),
            ("username", email),
            ("password", masterPasswordHash),
            ("deviceType", "1"),
            ("deviceIdentifier", deviceIdentifier),
            ("deviceName", "amparo-ios"),
        ]).utf8)
        let (data, http) = try await send(request)
        guard http.statusCode == 200 else {
            throw Self.passwordGrantFailure(status: http.statusCode, body: data)
        }
        let response: TokenResponse = try decode(data, context: "token")
        guard let newRefresh = response.refreshToken else {
            throw AmparoError.unexpectedResponse("password grant returned no refresh_token")
        }
        storeTokens(access: response.accessToken, refresh: newRefresh)
        return response
    }

    /// §6.3 refresh grant, single-flight: concurrent callers share one
    /// in-flight token request.
    @discardableResult
    public func refresh() async throws -> TokenPair {
        if let inFlight = refreshTask { return try await inFlight.value }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// `GET /api/sync?excludeDomains=true`. Reactive auth (D12): no access
    /// token → refresh first; 401 → refresh → retry once; a second 401 means
    /// the server no longer recognizes this device at all.
    public func sync() async throws -> SyncResponse {
        if accessToken == nil { try await refresh() }
        guard let token = accessToken else { throw AmparoError.reenrollRequired }
        if let response = try await requestSync(bearer: token) { return response }
        try await refresh()
        guard let retryToken = accessToken else { throw AmparoError.reenrollRequired }
        if let response = try await requestSync(bearer: retryToken) { return response }
        throw AmparoError.reenrollRequired
    }

    /// `GET {base}/icons/{domain}/icon.png`, unauthenticated (§6.5).
    /// 404 (no icon known) is a normal answer, not an error.
    public func fetchIcon(domain: String) async throws -> Data? {
        let escaped = domain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? domain
        let (data, http) = try await send(makeRequest("GET", "/icons/\(escaped)/icon.png"))
        switch http.statusCode {
        case 200: return data
        case 404: return nil
        default: throw AmparoError.unexpectedResponse("icon HTTP \(http.statusCode)")
        }
    }

    // MARK: Internals

    private func performRefresh() async throws -> TokenPair {
        guard let refreshToken else { throw AmparoError.reenrollRequired }
        var request = makeRequest("POST", "/identity/connect/token")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode([
            ("grant_type", "refresh_token"),
            ("client_id", "mobile"),
            ("refresh_token", refreshToken),
        ]).utf8)
        let (data, http) = try await send(request)
        switch http.statusCode {
        case 200:
            let response: TokenResponse = try decode(data, context: "refresh")
            // Rotation is the server's choice; keep the old token if the
            // response omits one.
            let pair = TokenPair(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? refreshToken
            )
            storeTokens(access: pair.accessToken, refresh: pair.refreshToken)
            return pair
        case 400:
            // Observed rejection body: {"error": "invalid_grant"}. Only this
            // definitive refusal earns the purge signal — transport failures
            // and 5xx never reach here (`send` maps them), so an offline
            // member keeps the local vault.
            throw AmparoError.reenrollRequired
        default:
            throw AmparoError.unexpectedResponse("refresh HTTP \(http.statusCode)")
        }
    }

    /// nil means 401 — the caller decides whether a refresh retry is left.
    private func requestSync(bearer: String) async throws -> SyncResponse? {
        var request = makeRequest("GET", "/api/sync", query: [URLQueryItem(name: "excludeDomains", value: "true")])
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request)
        switch http.statusCode {
        case 200: return try decode(data, context: "sync") as SyncResponse
        case 401: return nil
        default: throw AmparoError.unexpectedResponse("sync HTTP \(http.statusCode)")
        }
    }

    private func storeTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        onTokensUpdated?(TokenPair(accessToken: access, refreshToken: refresh))
    }

    /// All transport/network failures funnel through here: `URLError` →
    /// `.offline`, 5xx/429 → `.serverUnavailable`. Endpoint-specific 4xx
    /// handling stays with the callers.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.send(request)
        } catch let error as URLError {
            throw AmparoError.offline(error.code)
        } catch {
            throw AmparoError.offline(nil)
        }
        if (500...599).contains(http.statusCode) || http.statusCode == 429 {
            throw AmparoError.serverUnavailable(status: http.statusCode)
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ data: Data, context: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AmparoError.unexpectedResponse("\(context) decode: \(error)")
        }
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem]? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        return request
    }

    /// Classifies a non-200 password grant from observed bodies (captured
    /// samples, D14):
    /// - 2FA challenge: `error=invalid_grant` **plus** a `TwoFactorProviders*`
    ///   key — so the 2FA probe must run before anything keyed on `error`.
    /// - wrong password: `error` is empty; the prose lives in
    ///   `errorModel.message`. Any other 400 is therefore bad credentials.
    private static func passwordGrantFailure(status: Int, body: Data) -> AmparoError {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           object.keys.contains(where: { $0.lowercased().hasPrefix("twofactorproviders") }) {
            return .twoFactorRequired
        }
        guard status == 400 else {
            return .unexpectedResponse("token HTTP \(status)")
        }
        return .invalidCredentials
    }

    // MARK: Encoding helpers

    /// application/x-www-form-urlencoded per the HTML spec (what the server
    /// was validated against): unreserved = ALPHA / DIGIT / `*-._`,
    /// space → `+`, everything else percent-encoded.
    private static func formEncode(_ fields: [(String, String)]) -> String {
        func escape(_ string: String) -> String {
            var out = ""
            for byte in string.utf8 {
                switch byte {
                case UInt8(ascii: "a")...UInt8(ascii: "z"),
                     UInt8(ascii: "A")...UInt8(ascii: "Z"),
                     UInt8(ascii: "0")...UInt8(ascii: "9"),
                     UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                    out.append(Character(UnicodeScalar(byte)))
                case UInt8(ascii: " "):
                    out.append("+")
                default:
                    out.append(String(format: "%%%02X", byte))
                }
            }
            return out
        }
        return fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    private static func base64url(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
