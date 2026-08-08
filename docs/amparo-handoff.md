# amparo — Claude Code Handoff Package

**Working name:** `amparo` (pt-BR: support, protection; legal connotation of protective recourse). Rename freely; no code identifiers depend on it.
**Document status:** v1.0 — full SDLC handoff, iOS-first sequencing.
**Author/operator:** Kevin (Principal Technologist; 30+ yr systems; Rust/Swift/TS; local-first).
**Agent:** Claude Code, iterative sessions. This document is the single source of truth. Update the Decision Log (§12) as decisions land.

---

## 0. Mission

An open-source, free, Bitwarden-protocol-compatible system that lets a tech-savvy adult child ("caregiver") remotely manage credentials for an elderly parent ("member"), who gets a dead-simple, big-button, biometric-only iOS experience — one tap to fill a password, zero jargon, zero master-password prompts after enrollment.

**Not** a new password manager. The backend is stock **Vaultwarden** (self-hosted by the caregiver). The caregiver uses **official Bitwarden clients** for all management. We build only the **member-side iOS client**, clean-room, Apache-2.0.

### Product principles
1. **Member never sees:** vault, folder, collection, URI, TOTP, KDF, sync, master password — no password-manager vocabulary anywhere in member UI.
2. **Autofill is the product.** The app UI is the fallback. Most days the member never opens the app: QuickType suggestion → Face ID → filled.
3. **Parent owns the account.** Caregiver is instance admin + org owner + emergency-access grantee. This is both the architecture and the legal posture.
4. **Fail to a human.** Every error state terminates in one screen: "Something needs attention — call {caregiver}" with a giant call button. No retry dialogs, no error codes.
5. **Local-first.** Works offline from last sync. No third-party cloud. Tailscale-first deployment.

---

## 1. Phase plan (resequenced: iOS first)

| Phase | Deliverable | Status |
|---|---|---|
| **P0** | Repo scaffold, legal package, dev Vaultwarden stack, test fixtures | this handoff → immediate |
| **P1** | `AmparoKit` Swift package: crypto core + protocol client, full unit tests | immediate |
| **P2** | iOS app: enrollment, keychain, member UI | after P1 |
| **P3** | AutoFill Credential Provider extension + identity store | after P2 |
| **P4** | Field pilot (TestFlight, real device, real parent), hardening | after P3 |
| **P5** | Caregiver deployment kit (compose, Tailscale, runbooks, backup) | parallel w/ P4 |
| **P6** | Android client (fork of GPL Bitwarden Android, separate repo, GPL-3.0) | **blocked: no test device.** Candidates when ready: used Pixel 7a/8a (Swappa/BackMarket, ~$150–250), guaranteed Android 14+ for Credential Manager. |
| **P7** | Docs site, App Store submission, localization (en + pt-BR) | last |

Hardware on hand: iPhone 15 Pro (member-device test target), Apple Silicon Mac (build host). **Paid Apple Developer Program required** — the AutoFill Credential Provider entitlement and TestFlight are not available on free provisioning. Enroll before P3.

---

## 2. Architecture

```
┌──────────────────────────┐         ┌───────────────────────────┐
│ Caregiver                │         │ Member (parent)           │
│  • Official Bitwarden    │         │  • amparo iOS app         │
│    clients (any)         │         │  • amparo autofill ext    │
│  • Vaultwarden /admin    │  HTTPS  │  • Tailscale (always-on)  │
└────────────┬─────────────┘ (tailnet└─────────────┬─────────────┘
             │                or TLS)              │
             ▼                                     ▼
        ┌─────────────────────────────────────────────┐
        │ Vaultwarden (Docker, caregiver-hosted)      │
        │  • member account (parent-owned)            │
        │  • caregiver account                        │
        │  • Org "Family" → Collection shared to      │
        │    member (read-only)                       │
        │  • Emergency Access: caregiver = grantee    │
        └─────────────────────────────────────────────┘
```

**Data flow:** caregiver CRUDs credentials in the org collection from their own device → member app syncs on foreground/notification → decrypts locally → registers identities with iOS QuickType.

**Account/permission model (P0 runbook encodes this):**
- Vaultwarden `ADMIN_TOKEN` held by caregiver; `SIGNUPS_ALLOWED=false` after both accounts exist.
- Member account created with caregiver-generated high-entropy master password. Member never knows or uses it; it exists only for enrollment and caregiver recovery. Stored in caregiver's own vault.
- Org "Family", collection "Contas" (accounts): member added with read-only, no-password-viewing OFF (member must be able to view/fill — read-only + view). Caregiver = owner.
- Emergency Access: member grants caregiver **Takeover**, wait time 1 day. (Vaultwarden implements Emergency Access; requires SMTP configured.)
- Member's personal vault stays empty; everything lives in the collection so the caregiver can always manage it.

---

## 3. Repository layout (monorepo, `amparo/`)

```
amparo/
├── LICENSE                    # Apache-2.0
├── NOTICE
├── DISCLAIMER.md              # §10
├── TRADEMARKS.md              # §10
├── CLEANROOM.md               # §4 policy, verbatim
├── README.md
├── AmparoKit/                 # Swift package (P1)
│   ├── Sources/AmparoCrypto/  # KDF, HKDF-expand, EncString, AES-CBC, RSA
│   ├── Sources/AmparoAPI/     # prelogin, token, refresh, sync, models
│   └── Tests/                 # vectors + integration (against local VW)
├── AmparoApp/                 # Xcode project (P2/P3)
│   ├── Amparo/                # main app (SwiftUI)
│   ├── AmparoAutofill/        # ASCredentialProvider extension
│   └── AmparoShared/          # keychain, store, shared models
├── deploy/                    # P5: compose.yaml (vw+caddy), compose.tailscale.yaml,
│   │                          #     enrollment-runbook.md, backup (restic), smtp notes
├── fixtures/                  # test accounts, seeded ciphers, generation scripts
└── docs/
```

Everything Apache-2.0. **No GPL/AGPL code enters this repo, ever** (see §4). Android fork (P6) will be a separate repo under GPL-3.0 — never share code between them in either direction; `AmparoKit` cannot be reused there unless we dual-license our own code (we can — we own it; note in Decision Log when relevant).

---

## 4. CLEAN-ROOM POLICY (hard constraint — paste into CLAUDE.md)

The iOS client must be independently authored so it can carry Apache-2.0 and ship to the App Store without GPL entanglement.

**Prohibited inputs (never open, fetch, quote, or paraphrase-from):**
- Source of any Bitwarden client repo (`bitwarden/ios`, `bitwarden/android`, `bitwarden/clients`, `bitwarden/mobile`, `bitwarden/sdk*`) — GPL-3.0.
- Source of any third-party Bitwarden-compatible client (rbw, goldwarden, Keyguard, etc.) regardless of license — avoids taint arguments entirely.
- Vaultwarden **source code** (AGPL). Its **wiki/docs** are fine.

**Permitted inputs:**
- Bitwarden Security Whitepaper and help.bitwarden.com (documentation, not code).
- Vaultwarden wiki.
- Observed HTTP behavior of our own Vaultwarden instance (black-box traffic via mitmproxy against official clients is acceptable behavioral observation).
- Test vectors generated **behaviorally** with the official Bitwarden CLI (running a tool ≠ copying source).
- Apple documentation; RFCs (2898 PBKDF2, 5869 HKDF, 8018).
- This handoff document (§6 spec was written from documentation, not source).

**Process:** if Claude Code is ever uncertain whether an input is permitted, stop and ask. Log every external reference consulted in `docs/cleanroom-log.md` (URL, date, what was taken). Interfaces/wire formats are not copyrightable; expression is — we re-derive all expression.

---

## 5. Dev environment (P0)

```yaml
# deploy/compose.dev.yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    environment:
      - ADMIN_TOKEN=${ADMIN_TOKEN}
      - SIGNUPS_ALLOWED=true          # dev only
      - DOMAIN=https://vw.local.test
    ports: ["8222:80"]
    volumes: ["./vw-data:/data"]
```

- TLS for device testing: `mkcert` cert for a LAN hostname, or (preferred, matches prod) join the dev Mac + iPhone to the tailnet and use Tailscale HTTPS certs. iOS ATS requires valid TLS; do not fight ATS exceptions — use real certs from day one.
- Fixtures (`fixtures/seed.sh`): create caregiver + member accounts (PBKDF2 600k), org + collection, N=8 login ciphers with uri/username/password (+1 with TOTP, +1 org-less personal cipher to verify we handle both key paths). Use official `bw` CLI in the script (behavioral use, permitted).
- Integration tests in `AmparoKit` run against this stack (env-gated: `AMPARO_VW_URL`).

---

## 6. Protocol & crypto specification (clean-room source of truth)

Derived from the Bitwarden Security Whitepaper + public API documentation. Verify each item against live Vaultwarden traffic during P1; correct this section in-place if behavior differs (log in Decision Log).

### 6.1 KDF and keys
- **Prelogin:** `POST /identity/accounts/prelogin` `{"email": "<lowercase>"}` → `{kdf: 0|1, kdfIterations, kdfMemory?, kdfParallelism?}`. kdf 0 = PBKDF2-SHA256, 1 = Argon2id.
- **Master Key (32B):**
  - PBKDF2: `PBKDF2-SHA256(password=UTF8(masterPassword), salt=UTF8(lowercase(email)), iters=kdfIterations)` → 32 bytes.
  - Argon2id: salt = `SHA256(lowercase(email))`; params from prelogin (defaults 64 MiB / t=3 / p=4).
  - **Scope cut:** enrollment runbook pins member accounts to PBKDF2 600k. Argon2id lands in P4 via a vetted Swift/libsodium binding. App must hard-fail with the call-caregiver screen if prelogin returns kdf=1 before then.
- **Master Password Hash (auth):** `PBKDF2-SHA256(password=masterKey, salt=UTF8(masterPassword), iters=1)` → 32B → Base64. Sent as `password` in the token request.
- **Stretched Master Key (64B):** HKDF-**Expand-only** (RFC 5869 §2.3) with PRK = masterKey:
  - encKey = HKDF-Expand(PRK, info="enc", L=32)
  - macKey = HKDF-Expand(PRK, info="mac", L=32)
  - **Gotcha:** CryptoKit's `HKDF` runs Extract+Expand. Implement Expand manually (HMAC-SHA256 loop, T(1)=HMAC(PRK, info‖0x01)…). Unit-test against RFC 5869 vectors plus one full Bitwarden-derived vector.
- **User Symmetric Key (64B: 32 enc + 32 mac):** random per account; delivered encrypted ("protected key") in token/sync responses (`Key`), as an EncString type 2 under the Stretched Master Key.
- **RSA keypair:** user's private key (PKCS#8 DER) delivered as EncString type 2 under the User Symmetric Key (`PrivateKey`). Used to unwrap org keys.
- **Org Symmetric Key (64B):** per organization; delivered in sync `profile.organizations[].key` as EncString type 4 (RSA-2048-OAEP-SHA1) under the user's public key.

### 6.2 EncString wire format
`{encType}.{b64 part1}|{b64 part2}|{b64 part3}`

| Type | Scheme | Parts |
|---|---|---|
| 0 | AES-256-CBC (legacy, no MAC) | iv\|ct — decrypt-only, warn |
| 2 | AES-256-CBC + HMAC-SHA256 | iv\|ct\|mac |
| 3 | RSA-2048-OAEP-SHA256 | ct |
| 4 | RSA-2048-OAEP-SHA1 | ct |
| 5/6 | RSA + HMAC (deprecated) | ct\|mac — decrypt-only |

- Type 2 MAC input = `iv ‖ ct`, key = macKey half; **constant-time compare; verify MAC before decrypt**.
- AES-CBC via CommonCrypto (`CCCrypt`), PKCS#7 padding. HMAC/SHA via CryptoKit. RSA via `SecKeyCreateDecryptedData` (`.rsaEncryptionOAEPSHA1` / `...SHA256`).
- Implement `EncString` parse/serialize + `SymmetricCryptoKey` (64B split) as pure functions with exhaustive tests, including malformed-input fuzz cases.

### 6.3 Auth
- `POST /identity/connect/token`, `application/x-www-form-urlencoded`:
  `grant_type=password, scope=api offline_access, client_id=mobile, username=<email>, password=<masterPasswordHash b64>, deviceType=1 (iOS), deviceIdentifier=<stable UUID>, deviceName=amparo-ios`
  Header: `Auth-Email: base64url(email)`.
- Response: `access_token` (JWT, ~1–2h), `refresh_token`, `Key`, `PrivateKey`, `Kdf`, `KdfIterations`.
- Refresh: `grant_type=refresh_token`. On refresh failure (revocation, key rotation, deactivation): purge local state → call-caregiver screen. **Never** prompt the member for credentials.
- Observed against Vaultwarden (M2, captured in `AmparoKit/Tests/AmparoAPITests/Resources/`): refresh **does not rotate** the refresh token and its 200 body carries only the OAuth fields (no `Key`/`PrivateKey` — those come on the password grant); wrong password ⇒ 400 with **empty** `error` and the prose in `errorModel.message` (not `invalid_grant`); invalid/revoked refresh token ⇒ 400 bare `{"error":"invalid_grant"}`; 2FA challenge ⇒ 400 `invalid_grant` **plus** PascalCase `TwoFactorProviders`/`TwoFactorProviders2` keys — detect 2FA before classifying on `error`. Token bodies mix snake_case OAuth fields with PascalCase Bitwarden fields.
- 2FA: not used for the member account (runbook disables; the account is reachable only over the tailnet). If the server returns a 2FA challenge anyway → call-caregiver screen.
- New-device verification emails (Bitwarden 2024.12+ behavior): Vaultwarden exposes toggles; runbook disables for the member account. Client must still surface any unexpected 4xx as call-caregiver, never as raw error text.

### 6.4 Sync & models
- `GET /api/sync?excludeDomains=true` (Bearer) → `{profile, folders, collections, ciphers, policies, sends}`.
- We consume: `profile.key`, `profile.privateKey`, `profile.organizations[{id, key}]`, `ciphers[]`.
- Cipher (type 1 = Login only in v1): `{id, organizationId?, type, name(Enc), login: {username(Enc)?, password(Enc)?, totp(Enc)?, uris:[{uri(Enc), match?}]}, revisionDate, deletedDate?}` (observed: the trash marker is `deletedDate`, not `deleted`; sync bodies are camelCase).
- Key selection: `organizationId == nil` → User Symmetric Key; else org key. Both paths in fixtures.
- Persistence: single encrypted store (see §7.3). Poll on foreground + manual "Atualizar" in caregiver-hidden settings; WebSocket push is a P4 nice-to-have (Vaultwarden supports `/notifications/hub`).

### 6.5 Icons
`GET {base}/icons/{domain}/icon.png` (no auth). Cache aggressively; fall back to large monogram tiles.

---

## 7. iOS app specification (P2)

### 7.1 Targets
- iOS 17.0+, Swift 5.10+, SwiftUI, Xcode 16+. App Group `group.io.<org>.amparo`; shared Keychain Access Group. Two targets: app + autofill extension; both link `AmparoShared`.

### 7.2 Enrollment (caregiver-performed, on member device)
1. First-run → caregiver screen (English, technical): server URL, email, master password, caregiver display name + phone (for the call screen), consent attestation checkbox (§10.3).
2. Prelogin → derive → token → sync → full decrypt of User Symmetric Key + Private Key + org keys.
3. Persist to Keychain (§7.3). **Master password is zeroized and never stored.**
4. Register autofill identities; walk caregiver through Settings → General → AutoFill & Passwords → enable Amparo (deep-link where possible; show illustrated steps).
5. Hand device to member. Enrollment screens are reachable afterward only via hidden gesture (long-press 5s on the header) + caregiver PIN set during enrollment.

### 7.3 Key storage & unlock model
- Keychain items (access group shared with extension), `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`:
  - `userKey` (64B), `privateKey` (DER), `orgKeys` (dict) — protected with `SecAccessControl(.biometryCurrentSet)` → any read triggers Face ID automatically. This *is* the unlock UX; there is no lock screen in the app.
  - `refreshToken`, `serverURL`, `email`, config — passcode-only protection (no biometry) so background refresh/sync can run.
- Cipher cache: ciphers stored **encrypted as received** (EncStrings) in a local store (SQLite/GRDB or flat JSON — Claude Code's choice, log it); decrypt fields on demand with keys from Keychain. Memory hygiene: decrypted secrets in `Data` zeroized after use where practical.
- Biometry reset (Face ID re-enrolled) invalidates `.biometryCurrentSet` items → call-caregiver screen (caregiver re-enrolls; runbook covers).

### 7.4 Member UI (the actual product)
- **Home:** grid of large tiles (min 44pt targets — target ~120pt tiles), icon + site name only. Max ~8 visible; ordered by caregiver via cipher name prefix convention (`1. Banco`, `2. Email` — strip the prefix for display) — zero server-side custom fields needed. No search in v1 unless >12 items.
- **Detail (tap tile):** giant "Copiar senha / Copy password" button (copies, 60s clipboard expiry via `UIPasteboard` expiration), secondary "Mostrar / Show" reveal with auto-hide 30s, username shown large. If TOTP present: 64pt code with a countdown ring. Nothing else.
- **Typography:** Dynamic Type up to accessibility sizes; default to `.accessibility1`; WCAG AAA contrast; respect Reduce Motion; VoiceOver labels on everything.
- **Language:** en base; pt-BR localization scaffolded from day one (Kevin will polish strings).
- **Error surface (single):** call-caregiver screen — caregiver name, giant phone button (`tel:`), calm one-sentence copy. All failure paths route here.
- No settings, no onboarding, no tips, no badges, no notifications to the member.

---

## 8. AutoFill extension (P3)

- `AmparoAutofill` target: subclass `ASCredentialProviderViewController`; entitlement `com.apple.developer.authentication-services.autofill-credential-provider`.
- After every sync, populate `ASCredentialIdentityStore` with `ASPasswordCredentialIdentity(serviceIdentifier: <uri host>, user: <username>, recordIdentifier: <cipherId>)` → QuickType shows suggestions in Safari/apps without opening our UI.
- `provideCredentialWithoutUserInteraction(for:)`: read keys from Keychain (biometry fires system Face ID sheet), decrypt cipher, return `ASPasswordCredential`. If biometry unavailable → `userInteractionRequired` → minimal extension UI (same big-tile list, filtered by `serviceIdentifiers`).
- `prepareCredentialList(for:)`: big-tile picker, same visual language as app.
- v1 scope: passwords only. Passkey provider APIs (`prepareInterface(forPasskeyRegistration:)` etc.) explicitly deferred — delegation story isn't there yet.
- Verify autofill inside **Assistive Access** on the test device early in P3 (undocumented by Apple; from prior research, likely works since non-optimized apps get standard keyboard/UI — treat as an open risk, result goes in Decision Log). If blocked: ship without Assistive Access; app itself is the accessibility shell, optionally hardened with Guided Access.

---

## 9. Testing

- **Unit (P1):** RFC 5869 expand vectors; PBKDF2 vectors (RFC 6070-style + one full email/password→masterKey→hash chain validated against `bw` CLI behavior); EncString parse/roundtrip/fuzz; MAC tamper cases; RSA unwrap with fixture keypair.
- **Integration (P1/P2):** against dev Vaultwarden — prelogin/token/refresh/sync happy paths; revoked-token path; org + personal cipher decryption; icon fetch.
- **Device (P3/P4):** autofill in Safari + 3 real apps; Face ID re-enroll invalidation; offline behavior (airplane mode after sync); Assistive Access matrix; clipboard expiry.
- **Pilot (P4):** TestFlight to Kevin's own family device; 2-week diary of member friction points before any public release.

---

## 10. Legal package (P0, files in repo root)

### 10.1 DISCLAIMER.md (draft — refine, but keep substance)
- Software provided "AS IS" per Apache-2.0 §§7–8; no warranty; authors/contributors not liable.
- Amparo is a self-hosted tool operated entirely by its users. The authors run no service, hold no data, and have no access to any deployment.
- Users are solely responsible for compliance with the terms of service of any third-party account accessed using credentials stored in their deployment, and with all applicable laws.
- Amparo is intended **only** for use with the informed, ongoing consent and authorization of the account holder whose credentials are stored. Recommended: pair with a durable financial power of attorney. Nothing in this project is legal advice.
- Unofficial project; compatible with the Bitwarden® server API; **not affiliated with, endorsed by, or supported by Bitwarden, Inc.** (also in TRADEMARKS.md and README header).

### 10.2 TRADEMARKS.md
- "Bitwarden" and "Vaultwarden" used only nominatively to describe compatibility. No Bitwarden marks/logos/branding in the app, name, icon, or store listing. App name/bundle contains no "warden"/"bit" derivative.

### 10.3 In-app consent attestation (enrollment step 1)
Checkbox + stored locally (timestamp, caregiver name): "I confirm I am setting up this app with the knowledge, consent, and authorization of the account holder, and that I act on their behalf at their direction." Not exported anywhere; exists to put the representation on the operator and document intent.

### 10.4 Store posture (P7)
Listing copy: "assisted access for the account holder, managed by a helper they choose." Never "manage someone else's passwords / log into your parent's bank." Review may probe the caregiver model; the parent-owned-account architecture and consent flow are the answers.

---

## 11. Milestones & tasks

**M0 — Scaffold (P0)**
- M0-T1 repo layout per §3; Apache-2.0, NOTICE, DISCLAIMER, TRADEMARKS, CLEANROOM, CLAUDE.md (embed §4 + §0 principles).
- M0-T2 `deploy/compose.dev.yaml` + `fixtures/seed.sh` (accounts, org, 10 ciphers) + mkcert/Tailscale TLS notes.
- M0-T3 `docs/cleanroom-log.md` initialized.

**M1 — AmparoCrypto**
- M1-T1 HKDF-Expand-only + tests (RFC vectors).
- M1-T2 PBKDF2 master key + master password hash + tests.
- M1-T3 EncString parse/serialize; type 2 decrypt (MAC-then-decrypt, constant-time); type 0 decrypt-with-warning; fuzz tests.
- M1-T4 RSA OAEP unwrap (types 3/4); SymmetricCryptoKey; org-key path.
- M1-T5 End-to-end vector: fixture account → decrypt a known cipher, validated against `bw` CLI output.

**M2 — AmparoAPI**
- M2-T1 prelogin/token/refresh (+Auth-Email header, deviceIdentifier persistence).
- M2-T2 sync + models (Login ciphers, orgs, profile keys); decode-tolerant (unknown fields ignored).
- M2-T3 integration suite vs dev VW, incl. revoked-token → typed `AmparoError.reenrollRequired`.

**M3 — App**
- M3-T1 AmparoShared: Keychain layer (§7.3) incl. biometry-protected items + invalidation handling.
- M3-T2 Enrollment flow (§7.2) incl. consent attestation + caregiver PIN + hidden gesture.
- M3-T3 Member home grid + detail screen (§7.4), Dynamic Type/VoiceOver audit, pt-BR string scaffold.
- M3-T4 Sync-on-foreground + encrypted cipher store + icon cache.
- M3-T5 Call-caregiver screen; route ALL error paths.

**M4 — Autofill**
- M4-T1 Extension target + entitlement + identity-store registration post-sync.
- M4-T2 Without-user-interaction path; interaction-required fallback UI.
- M4-T3 Device test matrix incl. Assistive Access probe (log result).

**M5 — Pilot/hardening:** TestFlight, clipboard expiry verify, memory hygiene pass, WebSocket push (optional), Argon2id (optional).

**M6 (P5) — Deployment kit:** prod compose (VW+Caddy) + Tailscale variant, enrollment runbook (encodes §2 account model + member-account 2FA/new-device settings), restic backup unit, upgrade notes.

---

## 12. Decision log (append-only)

| # | Date | Decision | Rationale |
|---|---|---|---|
| D1 | 2026-08-08 | iOS clean-room first; Android fork deferred | No Android test device on hand |
| D2 | 2026-08-08 | Apache-2.0, monorepo excl. Android | App Store + GPL incompatibility for non-copyright-holders |
| D3 | 2026-08-08 | Member accounts pinned PBKDF2 600k at enrollment | Defer Argon2id dependency |
| D4 | 2026-08-08 | Ordering via name-prefix convention | Zero server/schema changes |
| D5 | 2026-08-08 | Cipher store = flat JSON (`VaultSnapshot` in the App Group container; ciphers persisted encrypted-as-received via Codable EncStrings, §7.3) | Tens of items at most; nothing at rest is plaintext; GRDB would be the repo's first dependency for no measurable gain |
| D6 | 2026-08-08 | Dev container runtime = podman (+ docker-compose provider) | No Docker Desktop on build host; compose file stays runtime-agnostic |
| D7 | 2026-08-08 | Fixture seeding = Node register-helper (§6 crypto, stdlib) for accounts/org/invite/confirm + official `bw` CLI for all ciphers | `bw` cannot register accounts or create orgs (web-vault-only flows); helper's derivations double as behavioral test vectors for P1; ciphers stay canonical (created by official tooling) |
| D8 | 2026-08-08 | Dev stack adds Caddy TLS sidecar (internal CA) at `https://localhost:8443`; plain HTTP kept on 8222 for debugging | `bw` CLI 2025.x refuses plain-HTTP server URLs; also matches "real certs from day one" posture |
| D9 | 2026-08-08 | AmparoKit: swift-tools 6.0, swift-testing for unit tests | Toolchain on hand is Swift 6.3/Xcode 26; exceeds handoff's 5.10/16 minimums |
| D10 | 2026-08-08 | M1 vectors = committed `e2e-vectors.json`, generated behaviorally (`fixtures/gen-vectors.mjs`: raw EncStrings from live API, plaintexts from `bw`) | Unit tests run offline; regenerate after re-seed; dev-only key material, committing intended |
| D11 | 2026-08-08 | EncString: types 5/6 parse but refuse decrypt; type 1 (AES-128) rejected as unknown | Outside §6.2 table / never emitted by target servers; no test data exists to validate a decrypt path |
| D12 | 2026-08-08 | AmparoAPI = one `VaultwardenClient` actor over a 1-method `HTTPTransport` protocol; tokens in actor memory only; refresh-token durability + deviceIdentifier persistence delegated to caller via init params + `onTokensUpdated` (M3 Keychain); sync auth is reactive 401→refresh→retry-once, single-flight | Sendable-correct token state under Swift 6 strict concurrency; trivial unit stubbing; package stays Keychain-free and zero-dependency; app and autofill extension each own a client |
| D13 | 2026-08-08 | Decoding: shared lowercase-first-letter custom key strategy (Swift transposition of the fixtures' `field()` accessor); `EncString` gains Codable in AmparoCrypto; ciphers lossy-decoded (bad element dropped, non-Login kept but filtered from `loginCiphers`); profile decodes strictly; dates stay `String` until M3 | Token bodies mix casings, sync is camelCase (captured samples); one exotic cipher must not kill sync, but an account without keys is unusable |
| D14 | 2026-08-08 | `AmparoError` = 7 cases, each mapped to one member outcome (purge+call / retry-later / call-caregiver). 2FA detected via `TwoFactorProviders*` key in the token 400 body, validated against a real captured challenge (`token-2fa.json`, throwaway authenticator-2FA account); wrong password classified as any non-2FA 400 because Vaultwarden sends empty `error` there | Handoff principle 4: the app maps cases, never surfaces raw errors; captured bodies beat guessed OAuth shapes — observed wrong-password is **not** `invalid_grant` |
| D15 | 2026-08-08 | Revoked-token coverage = garbage refresh token in the integration suite (server's real `invalid_grant` → `.reenrollRequired`); admin-deauth variant deferred as hardening. Raw API samples committed under `AmparoAPITests/Resources/` (extends D10); transport/5xx failures during refresh are `offline`/`serverUnavailable`, never the purge signal | Deterministic, zero ADMIN_TOKEN plumbing, no server-state mutation; offline members must keep the local vault (principle 5) |
| D16 | 2026-08-08 | AmparoShared lives in the AmparoKit package (not the Xcode project): `KeychainStore` over a SecItem seam, `VaultStore` actor with session-cached keys (`lock()` on background; Face ID fires on first read), biometry invalidation detected as protected-item-missing-while-enrolled | Unit-testable with `swift test` (fake keychain, captured samples drive full offline enrollment with real crypto); one Face ID per foreground session instead of per secret |
| D17 | 2026-08-08 | Purge (`VaultStore.reset()`, reenroll-required path) keeps `caregiverProfile` + `consentRecord`; everything else goes | The only screen after a purge is call-caregiver — it needs the phone number; the consent attestation is the operator's legal record and must survive resets |
| D18 | 2026-08-08 | App scaffold: xcodegen `project.yml` committed, `.xcodeproj` gitignored; bundle root `onl.kev.amparo` (Kevin owns kev.onl); keychain sharing via the App Group id (`group.onl.kev.amparo`) rather than an AppIdentifierPrefix group; member UI Dynamic Type clamped to `.accessibility1+`; TOTP implemented in AmparoCrypto from RFC 4226/6238 | Regenerable project, reviewable config; app-group keychain works identically for the M4 extension without hardcoding the team ID; §7.4 accessibility default; autofill (M4) needs TOTP-on-fill anyway |

## 13. Open questions
- Assistive Access × third-party autofill: empirical answer needed (M4-T3).
- Vaultwarden WebSocket push payload shape (behavioral capture in P4 if pursued).
- TOTP: render only, or hide entirely for members whose sites use SMS? (Pilot decides.)
- Dual-licensing AmparoKit for the future GPL Android repo: decide at P6.

## 14. Session bootstrap for Claude Code
1. Read this file end-to-end; read CLEANROOM.md; confirm constraints.
2. Execute M0 fully before writing any Swift.
3. One milestone per session where possible; run tests before ending a session; update Decision Log + cleanroom log in the same commit.
4. Never fetch prohibited repos (§4) — including via search results. When protocol behavior is ambiguous, test against the local Vaultwarden and document.
