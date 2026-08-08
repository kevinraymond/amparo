# Dev fixtures

Seeds the local dev Vaultwarden (see `deploy/compose.dev.yaml`) with the
account model from the handoff (§2) and test ciphers (§5). **Everything here
is throwaway dev data — the credentials in this directory and in
`fixtures.env` are intentionally committed and must never be real.**

```sh
podman compose -f deploy/compose.dev.yaml up -d   # from repo root
./fixtures/seed.sh                                # idempotent; re-run freely
```

Requires node ≥ 18 and the official Bitwarden CLI (`npm i -g @bitwarden/cli`).
`seed.sh` keeps all `bw` state in `fixtures/.bw/` (gitignored) and never
touches a real Bitwarden CLI config.

## How it seeds

1. `register-helper.mjs` — accounts and org, via the server HTTP API with the
   §6 crypto implemented in Node stdlib (the official CLI cannot register
   accounts or create orgs). Idempotent: it logs in first and only creates
   what's missing. Its derivations double as behavioral test vectors for
   AmparoKit.
2. `bw` CLI — all ciphers, so vault content is produced by official tooling
   and AmparoKit decrypts canonical data.

Results (IDs, URLs, credentials) land in `fixtures.env`; integration tests
read `AMPARO_VW_URL` from it (handoff §5).

## Generated test resources (re-run after re-seeding, in this order)

```sh
./fixtures/seed.sh
node fixtures/gen-vectors.mjs        # → AmparoKit/.../AmparoCryptoTests/Resources/e2e-vectors.json
node fixtures/capture-samples.mjs    # → AmparoKit/.../AmparoAPITests/Resources/*.json
```

- `gen-vectors.mjs` — M1 crypto vectors: raw EncStrings from the live API,
  expected plaintexts from official `bw` output.
- `capture-samples.mjs` — M2 API samples: raw HTTP bodies (prelogin, token
  success/wrong-password/invalid-refresh/2FA-challenge, sync), each enveloped
  as `{captured, request, status, body}`. The 2FA sample comes from a
  dedicated throwaway account (`twofa-sample@amparo.test`) that is created
  once and kept with authenticator 2FA enabled so re-runs are instant; it is
  invisible to `seed.sh` and the member/caregiver fixtures.

`sync-success.json` and `e2e-vectors.json` covary (cipher IDs and EncStrings
change on re-seed) — always regenerate both together.

## What gets created

| | |
|---|---|
| Accounts | `caregiver@amparo.test`, `member@amparo.test` — PBKDF2-SHA256, 600k iterations |
| Org | `Family`, owned by caregiver |
| Collection | `Contas`, member has read-only + can view passwords |
| Org ciphers | `1. Banco` … `8. Luz` (login: uri/username/password), `9. Previdencia` (+ TOTP) — created by caregiver, decrypt via the **org-key path** |
| Personal cipher | `Portal Medico` in the member's own vault — decrypts via the **user-key path** |

Cipher names use the ordering-prefix convention from handoff §7.4 / D4.

## Server endpoints

- `http://localhost:8222` — plain HTTP, for curl/debugging and simple tests.
- `https://localhost:8443` — Caddy TLS sidecar with an internal CA; modern
  Bitwarden clients refuse plain-HTTP server URLs, so `bw` uses this. Trust
  it via `NODE_EXTRA_CA_CERTS=deploy/caddy-data/caddy/pki/authorities/local/root.crt`
  (also written to `fixtures.env` as `AMPARO_VW_CA_CERT`).

## Resetting from scratch

```sh
podman compose -f deploy/compose.dev.yaml down
rm -rf deploy/vw-data deploy/caddy-data fixtures/.bw
podman compose -f deploy/compose.dev.yaml up -d
./fixtures/seed.sh
```

## Dev-only caveats (differences from a real deployment)

- `SIGNUPS_ALLOWED=true`; production runbook (P5) sets it false after both
  accounts exist.
- No SMTP → org invites auto-accept (observed behavior), and **Emergency
  Access cannot be exercised here** — it requires SMTP; that's a P5 runbook
  concern.
- 2FA and new-device verification are off (no SMTP), matching the intended
  member-account posture anyway.
