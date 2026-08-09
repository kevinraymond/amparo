# Project status

Cross-session tracker. **Update in the same commit as the work it records**
(with the Decision Log in `amparo-handoff.md` §12 and `cleanroom-log.md`).
The handoff doc defines the tasks; this file records their state. One session
≈ one milestone where possible.

## Milestones

### M0 — Scaffold (P0) ✅ 2026-08-08
- [x] M0-T1 repo layout, legal package (LICENSE/NOTICE/DISCLAIMER/TRADEMARKS/CLEANROOM), CLAUDE.md
- [x] M0-T2 dev stack (`deploy/compose.dev.yaml`: Vaultwarden + Caddy TLS sidecar, runs under podman) + `fixtures/seed.sh` (accounts, Family/Contas, 10 ciphers, idempotent) + TLS notes
- [x] M0-T3 `docs/cleanroom-log.md` initialized

### M1 — AmparoCrypto (P1) ✅ 2026-08-08
- [x] M1-T1 HKDF-Expand-only + RFC 5869 A.1–A.3 vectors
- [x] M1-T2 PBKDF2 master key + master password hash + full-chain vector (RFC 7914 §11 + behavioral)
- [x] M1-T3 EncString parse/serialize; type 2 MAC-then-decrypt (constant-time); type 0 legacy; fuzz/tamper
- [x] M1-T4 RSA OAEP unwrap (types 3/4, PKCS#8→PKCS#1 DER unwrap); SymmetricCryptoKey; org-key path
- [x] M1-T5 E2E vector: `AccountUnlock` chain decrypts all 3 fixture ciphers = `bw` output (`e2e-vectors.json`; regenerate with `fixtures/gen-vectors.mjs` after re-seed)

### M2 — AmparoAPI (P1) ✅ 2026-08-08
- [x] M2-T1 prelogin/token/refresh (`VaultwardenClient` actor + `HTTPTransport` seam; Auth-Email unpadded b64url on password grant only; exact form encoding pinned by tests)
- [x] M2-T2 sync + models (lossy cipher decode, casing-tolerant decoder, `EncString` Codable, reactive 401→refresh→retry-once single-flight, icons)
- [x] M2-T3 integration suite vs dev VW (env-gated `AMPARO_VW_URL`, self-skips with pointer) incl. garbage-refresh-token → `AmparoError.reenrollRequired` (D15)

### M3 — App (P2) — code complete 2026-08-08, device pass pending
- [x] M3-T1 Keychain layer (AmparoShared in AmparoKit: SecItem seam, biometry vs passcode tiers, invalidation detection)
- [x] M3-T2 enrollment flow (consent attestation §10.3, caregiver PIN, hidden 5s-hold + PIN re-entry, autofill walkthrough placeholder)
- [x] M3-T3 member home grid + detail (prefix-stripped tiles, copy w/ 60s clipboard expiry, reveal 30s auto-hide, TOTP 64pt + ring, Dynamic Type clamped a11y1+, VoiceOver labels, en+pt-BR xcstrings)
- [x] M3-T4 sync-on-foreground + flat-JSON snapshot store (D5) + icon cache w/ negative caching
- [x] M3-T5 call-caregiver screen; all member error paths route there (purge keeps caregiver contact, D17)
- Device build ✅ signed with the paid team + App Group profile; **Amparo 0.1.0 installed on the test device** via devicectl. (Root cause of the earlier "No Account for Team": the project carried the stale *free* personal-team ID from an old cert — paid enrollment creates a different team ID. Also: app groups must not be listed under `keychain-access-groups` — the App Groups entitlement alone grants keychain sharing.)
- Device pass round 1 done (2026-08-08): enrollment + tiles + detail + TOTP + offline→call-screen all exercised. Findings fixed same day (D19): double Face ID (→ single `vaultKeys` blob), stuck call screen (→ self-heal + hidden door), top gap, button/username wrapping, reveal countdown added. **Note: the keychain layout changed — re-enroll once via the call screen's hidden door (hold headline 5 s → PIN → Reset enrollment).**
- **Pending on-device round 2:** re-enroll + re-verify the fixes; still open from the audit list: biometry re-enroll invalidation, VoiceOver pass, clipboard expiry verify. QR-assisted enrollment logged as §13 open question.

### M4 — Autofill (P3) — code complete 2026-08-08, device matrix pending
- [x] M4-T1 AmparoAutofill extension target (autofill entitlement + app group, provisioned via automatic signing) + `CredentialIdentityRegistrar` (post-unlock replace-all, §8 amended per D20) + `AutofillMatcher` (unit-tested)
- [x] M4-T2 no-interaction fill (biometry keychain read → system Face ID sheet → `ASPasswordCredential`; keychain failures → `userInteractionRequired`), interactive unlock fallback, big-tile picker filtered by service
- [x] M4-T3 device matrix ✅ 2026-08-08 (D21): picker fill in Safari + 3 real apps; **works inside Assistive Access** (§8 risk resolved); QuickType shows generic "Passwords" affordance on the multi-provider test device (re-verify inline chip on a sole-provider member device); no-interaction leg pending an inline-chip fill; extension monogram tiles → M5 icon polish.

### M4.5 — Backend-agnostic auth (D22/D23, handoff v1.1) — pending
- [ ] `Environment` struct + cloud presets (§6.3a) · API-key `client_credentials` auth replacing password grant (§6.3) · keychain tier swap (apiClientId/Secret/Environment) · enrollment UI fields · M2-T1b behavioral verify vs dev VW **and** a throwaway cloud account · migration/re-enroll story for enrolled devices

### M5 — Pilot/hardening (P4) — pending (incl. colorblind-friendly themes + one-time-code autofill, both added from device feedback 2026-08-08; standing rule meanwhile: no meaning by hue alone; passkeys stay deferred per §8)
### M6 — Deployment kit (P5) — pending
### Android (P6) — blocked: no test device · Docs/store (P7) — last

## Session log

| Date | Scope | Result |
|---|---|---|
| 2026-08-08 | M0 complete | Commit `044f5f6`. Dev stack live (`http://localhost:8222`, `https://localhost:8443` via Caddy internal CA), fixtures seeded + idempotent. §6.1–6.3 crypto behaviorally validated via `fixtures/register-helper.mjs` (accounts/org/confirm) + official `bw` (ciphers). Decisions D6–D8. |
| 2026-08-08 | M1 complete | AmparoKit package (tools 6.0, swift-testing): AmparoCrypto full §6 crypto, 26 tests green in ~0.1s. AmparoAPI is a buildable placeholder for M2. Vector pipeline: `fixtures/gen-vectors.mjs` → committed `e2e-vectors.json`. Decisions D9–D11. This file + CLAUDE.md pointer added. |
| 2026-08-08 | M2 complete | AmparoAPI protocol client: 26 new unit tests (captured-sample driven) + 7 integration tests, 59 total green; integration decrypts all 10 fixture ciphers via both key paths against live VW. New `fixtures/capture-samples.mjs` → committed raw API samples incl. real 2FA challenge (throwaway authenticator account, kept for re-runs). Observed + documented: no refresh-token rotation; wrong-password ≠ `invalid_grant`; `deletedDate` (§6.3/§6.4 corrected in place). Decisions D12–D15. |
| 2026-08-08 | M3 code complete | AmparoShared (Keychain/store/VaultStore/icons) + TOTP in AmparoCrypto: 96 package tests green (offline enrollment test runs real crypto against captured samples, keys cross-checked vs e2e-vectors). SwiftUI app (enrollment, member grid/detail, call-caregiver, hidden caregiver settings) builds green for iPhone 17 Pro sim; `AmparoApp/project.yml` via xcodegen, bundle `onl.kev.amparo`. Device build blocked on Xcode account re-auth (see M3 action item). Decisions D5, D16–D18. |
| 2026-08-08 | M3 device deploy | "No Account for Team" root-caused: stale free-team ID in project.yml, not an auth issue → corrected `DEVELOPMENT_TEAM`; dropped app group from `keychain-access-groups` (App Groups entitlement suffices). Device build signed + provisioned; Amparo 0.1.0 installed on the test device. On-device pass now in Kevin's hands. |
| 2026-08-08 | Tailnet dev TLS live | Tailscale app on Mac (node renamed) + test iPhone on tailnet; HTTPS certs enabled tailnet-wide; `tailscale serve --bg http://localhost:8222` → the tailnet dev URL (tailnet-only, real LE cert, ATS-clean; see gitignored `deploy/dev-local.md`). `/alive` + prelogin verified through the proxy. `deploy/dev-tls-notes.md` updated with the live setup; on-device enrollment unblocked. |
| 2026-08-08 | Device-pass fixes | Kevin's round-1 findings → D19: single biometry blob (one Face ID/session, regression-tested), call screen self-heals + hidden caregiver door (PIN survives purge), home-grid gap, detail no-wrap + reveal countdown. 97 tests green; 0.1.0 rebuilt + reinstalled on the test device. Globe icons = VW fallback for fake fixture domains (expected); QR enrollment → §13. |
| 2026-08-08 | M4 code complete | AmparoAutofill extension (onl.kev.amparo.autofill): no-interaction fill, interactive fallback, filtered big-tile picker; identity registration post-unlock (D20, §8 amended); AutofillMatcher + mapping unit-tested (102 tests green). Autofill entitlement provisioned via automatic signing; installd taught us appex needs CFBundleDisplayName. Installed on the test device. M4-T3 device matrix + Assistive Access probe = Kevin. |
| 2026-08-08 | Publish prep | README launch revision (Kevin) + review; repo de-personalized for forks: `AmparoIdentifiers` now derives keychain/app-group from the bundle id at runtime, team ID moved to gitignored `AmparoApp/project-local.yml` (bootstrap via `generate.sh`), operator values (tailnet URL, device name, team) moved to gitignored `deploy/dev-local.md`. Screenshot shot-list in `docs/screenshots/`. Fixture creds stay committed by design (fake, required to use the seeded stack). Pushed to github.com/kevinraymond/amparo. |
| 2026-08-08 | M4 COMPLETE | M4-T3 results in (D21): picker fill Safari + 3 apps ✓; **Assistive Access ✓** — the biggest deployment unknown resolved in our favor. Handoff v1.1 (Kevin): cloud Bitwarden support via Environment presets + unified API-key auth — merged with restored in-repo history (his D6/D7 renumbered D22/D23; §6.3/§6.4/§7.3/§8/M5/§12/§13 amendments re-applied); new milestone M4.5 created for the auth migration. |

## Environment notes (dev host)

- Container runtime: podman (`podman machine start` first) + docker-compose provider; no Docker Desktop.
- `bw` CLI installed globally via npm; 2025.x refuses plain-HTTP server URLs → use `https://localhost:8443` + `NODE_EXTRA_CA_CERTS` (see `fixtures/README.md`).
- Toolchain: Swift 6.3 / Xcode 26.6 on Apple Silicon; test device iPhone 15 Pro (paired via devicectl; name in `deploy/dev-local.md`).
- `xcodegen` (homebrew) generates `AmparoApp/Amparo.xcodeproj` from the committed `project.yml`; the project itself is gitignored.
- Signing: team ID lives in gitignored `AmparoApp/project-local.yml` (real values in `deploy/dev-local.md`). Beware stale free-personal-team identities in the login keychain.
