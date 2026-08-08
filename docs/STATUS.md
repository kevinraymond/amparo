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

### M2 — AmparoAPI (P1) — pending
- [ ] M2-T1 prelogin/token/refresh
- [ ] M2-T2 sync + models
- [ ] M2-T3 integration suite vs dev VW (env-gated `AMPARO_VW_URL`)

### M3 — App (P2) — pending
- [ ] M3-T1 Keychain layer · M3-T2 enrollment · M3-T3 member UI · M3-T4 sync/store/icons · M3-T5 call-caregiver screen
- Blocker before P3: **paid Apple Developer Program enrollment** (autofill entitlement + TestFlight)

### M4 — Autofill (P3) — pending
- [ ] M4-T1 extension + identity store · M4-T2 no-interaction path · M4-T3 device matrix incl. Assistive Access probe

### M5 — Pilot/hardening (P4) — pending
### M6 — Deployment kit (P5) — pending
### Android (P6) — blocked: no test device · Docs/store (P7) — last

## Session log

| Date | Scope | Result |
|---|---|---|
| 2026-08-08 | M0 complete | Commit `044f5f6`. Dev stack live (`http://localhost:8222`, `https://localhost:8443` via Caddy internal CA), fixtures seeded + idempotent. §6.1–6.3 crypto behaviorally validated via `fixtures/register-helper.mjs` (accounts/org/confirm) + official `bw` (ciphers). Decisions D6–D8. |
| 2026-08-08 | M1 complete | AmparoKit package (tools 6.0, swift-testing): AmparoCrypto full §6 crypto, 26 tests green in ~0.1s. AmparoAPI is a buildable placeholder for M2. Vector pipeline: `fixtures/gen-vectors.mjs` → committed `e2e-vectors.json`. Decisions D9–D11. This file + CLAUDE.md pointer added. |

## Environment notes (dev host)

- Container runtime: podman (`podman machine start` first) + docker-compose provider; no Docker Desktop.
- `bw` CLI installed globally via npm; 2025.x refuses plain-HTTP server URLs → use `https://localhost:8443` + `NODE_EXTRA_CA_CERTS` (see `fixtures/README.md`).
- Toolchain: Swift 6.3 / Xcode 26.6 on Apple Silicon; test device iPhone 15 Pro.
