import Foundation

/// The API layer's complete failure vocabulary. Every case maps to exactly
/// one member outcome (handoff principle 4 — all roads end at the
/// call-caregiver screen; what varies is whether local state survives):
///
/// | Case                 | Member outcome                                  |
/// |----------------------|-------------------------------------------------|
/// | `reenrollRequired`   | purge local state + call caregiver              |
/// | `invalidCredentials` | enrollment-time only, shown to the caregiver    |
/// | `twoFactorRequired`  | call caregiver (runbook keeps member 2FA off)   |
/// | `unsupportedKdf`     | call caregiver (Argon2id deferred, D3)          |
/// | `offline`            | retry later; local state untouched              |
/// | `serverUnavailable`  | retry later; local state untouched              |
/// | `unexpectedResponse` | call caregiver; detail is for logs only, never UI |
public enum AmparoError: Error, Equatable, Sendable {
    case reenrollRequired
    case invalidCredentials
    case twoFactorRequired
    case unsupportedKdf(kdf: Int)
    case offline(URLError.Code?)
    case serverUnavailable(status: Int)
    case unexpectedResponse(String)
}
