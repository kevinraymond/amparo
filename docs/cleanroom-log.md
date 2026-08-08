# Clean-room log

Append-only record of every external reference consulted while building
amparo, per [CLEANROOM.md](../CLEANROOM.md). Interfaces and wire formats are
not copyrightable; expression is — we re-derive all expression.

| Date | Source | What was taken |
|---|---|---|
| 2026-08-08 | `docs/amparo-handoff.md` (project handoff, written from documentation) | Full spec: protocol/crypto (§6), account model, phase plan |
| 2026-08-08 | https://www.apache.org/licenses/LICENSE-2.0.txt | Canonical Apache-2.0 license text → `LICENSE` |
| 2026-08-08 | Our own dev Vaultwarden instance (black-box HTTP probing, permitted) | Observed for `fixtures/register-helper.mjs`: classic `POST /identity/accounts/register` works; org create / user invite / confirm payload shapes; org invites auto-accept when SMTP is disabled; §6.1–6.3 derivations (PBKDF2 600k → master key → hash; HKDF-Expand enc/mac; EncString type 2; RSA-OAEP-SHA1 type 4) validated end-to-end by successful login + member decryption |
| 2026-08-08 | Official `bw` CLI 2025.x (behavioral use, permitted) | Cipher creation + vault verification for fixtures; observed: current CLI refuses plain-HTTP server URLs → dev stack gained the Caddy TLS sidecar |
| 2026-08-08 | RFC 5869 (HKDF), Appendix A | SHA-256 test vectors A.1–A.3 (PRK/info/OKM) → `HKDFTests.swift` |
| 2026-08-08 | RFC 7914 (scrypt), §11 | PBKDF2-HMAC-SHA256 test vectors → `MasterKeyTests.swift` |
| 2026-08-08 | Apple SDK documentation (CryptoKit HMAC, CommonCrypto CCKeyDerivationPBKDF/CCCrypt, Security SecKeyCreateWithData/SecKeyCreateDecryptedData) | API usage for AmparoCrypto; noted SecKey requires PKCS#1 → minimal DER unwrap of PKCS#8 |
| 2026-08-08 | Official `bw` CLI + our own dev Vaultwarden (behavioral, permitted) | `fixtures/gen-vectors.mjs`: E2E vector JSON — raw EncStrings from live API, expected plaintexts from `bw` output → `e2e-vectors.json` |
| 2026-08-08 | RFC 4226 (HOTP) + RFC 6238 (TOTP) incl. Appendix B vectors; RFC 4648 §10 (base32 vectors) | `TOTP.swift` algorithm + `TOTPTests.swift` vectors; fixture-secret codes additionally cross-checked against an independent Node-stdlib implementation |
| 2026-08-08 | Apple SDK documentation (Security: SecAccessControlCreateWithFlags/.biometryCurrentSet, SecItem*, kSecAttrAccessible*; SwiftUI; UIPasteboard expirationDate/localOnly options; FileManager App Group container) | API usage for AmparoShared + the M3 app: biometry-protected keychain items, clipboard expiry, App Group storage |
| 2026-08-08 | Apple SDK documentation (AuthenticationServices: ASCredentialProviderViewController, ASCredentialIdentityStore, ASPasswordCredentialIdentity/Credential, ASCredentialRequest, ASExtensionError; app-extension NSExtension plist keys) | API usage for the M4 autofill extension + identity registration; observed behaviorally: installd rejects an appex whose Info.plist lacks CFBundleDisplayName |
| 2026-08-08 | Our own dev Vaultwarden instance (black-box HTTP probing, permitted) | `fixtures/capture-samples.mjs` → committed M2 samples (prelogin/token/sync bodies + error shapes). Observed for AmparoAPI: wrong password ⇒ 400 with empty `error` + `errorModel.message` (not `invalid_grant`); garbage refresh token ⇒ 400 bare `{"error":"invalid_grant"}`; authenticator-2FA challenge ⇒ 400 `invalid_grant` + `TwoFactorProviders`/`TwoFactorProviders2` (PascalCase); token body mixes snake_case OAuth + PascalCase Bitwarden fields; sync body camelCase, trash marker is `deletedDate` (§6.4 corrected); refresh does **not** rotate the refresh token and returns OAuth fields only (no `Key`/`PrivateKey`); 2FA enable flow for the sample account: `POST /api/two-factor/get-authenticator` + `PUT /api/two-factor/authenticator` |
