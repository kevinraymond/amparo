# amparo

> Unofficial project. Compatible with the Bitwarden® server API; **not
> affiliated with, endorsed by, or supported by Bitwarden, Inc.** See
> [TRADEMARKS.md](TRADEMARKS.md) and [DISCLAIMER.md](DISCLAIMER.md).

An open-source, free system that lets a tech-savvy adult child (the
**caregiver**) remotely manage credentials for an elderly parent (the
**member**), who gets a dead-simple, big-button, biometric-only iOS
experience — one tap to fill a password, zero jargon, zero master-password
prompts after enrollment.

Amparo (pt-BR: support, protection) is **not** a new password manager. The
backend is stock [Vaultwarden](https://github.com/dani-garcia/vaultwarden),
self-hosted by the caregiver (the reference, Tailscale-first deployment), or
a cloud Bitwarden account for caregivers who won't self-host (spec §2.1;
client support lands in M4.5). The caregiver manages everything with official
Bitwarden clients. This repo builds only the **member-side iOS client** —
clean-room, Apache-2.0.

## How it works

- The caregiver hosts Vaultwarden (or uses cloud Bitwarden) and manages
  credentials in an org collection shared read-only to the member's account.
- The member's account is owned by the member (the parent). The caregiver is
  instance admin, org owner, and emergency-access grantee — that is both the
  architecture and the legal posture (see [DISCLAIMER.md](DISCLAIMER.md)).
- The amparo iOS app syncs, decrypts locally, and registers credentials with
  iOS QuickType. Most days the member never opens the app: autofill
  suggestion → Face ID → filled. In-app, the fallback is a big-tile grid with
  one-tap copy and TOTP codes.
- Every error path ends in one screen: "call your caregiver", with a giant
  call button. Face ID is the only unlock; there is no lock screen, no
  settings, no password-manager vocabulary anywhere in the member UI.

Full specification, phase plan, and decision log:
**[docs/amparo-handoff.md](docs/amparo-handoff.md)**.

## Status (2026-08)

Working end-to-end on a real device: enrollment → sync → member UI →
AutoFill in Safari and third-party apps — **including inside Assistive
Access** (D21).

| Milestone | State |
|---|---|
| M0 scaffold/dev stack · M1 crypto core · M2 protocol client · M3 member app · M4 autofill extension | ✅ complete |
| M4.5 backend-agnostic auth — cloud Bitwarden presets + unified API-key flow (D22/D23) | next |
| M5 pilot/hardening — TestFlight, colorblind themes, one-time-code autofill | pending |
| M6 caregiver deployment kit — prod compose, runbooks, backup | pending |
| Android client | deferred (no test device) |

Session-by-session detail: [docs/STATUS.md](docs/STATUS.md).

## Repository layout

```
AmparoKit/        Swift package (zero dependencies)
                    AmparoCrypto — KDF/HKDF/EncString/RSA/TOTP, RFC + behavioral vectors
                    AmparoAPI   — prelogin/token/sync client, captured-sample tests
                    AmparoShared — keychain (biometry blob), snapshot store, VaultStore, autofill identities
AmparoApp/        xcodegen project: member app (Amparo) + AutoFill extension (AmparoAutofill)
deploy/           Dev compose stack (Vaultwarden + Caddy TLS), Tailscale dev TLS notes
fixtures/         Dev seed: accounts, org, 11 test ciphers, vector/sample generators
docs/             Handoff spec (source of truth), STATUS, clean-room log
```

## Development

Contributions must follow **[CLEANROOM.md](CLEANROOM.md)** — never read
Bitwarden/Vaultwarden client or server source. External references consulted
go in `docs/cleanroom-log.md`.

### Dev server

Requires a container runtime (podman or Docker) with a compose provider, plus
Node ≥ 18 and the official Bitwarden CLI (`npm i -g @bitwarden/cli`) for
seeding.

```sh
cp deploy/.env.example deploy/.env   # then set a real ADMIN_TOKEN
podman compose -f deploy/compose.dev.yaml up -d
curl http://localhost:8222/alive
./fixtures/seed.sh                    # accounts, org, 11 test ciphers (idempotent)
```

See [fixtures/README.md](fixtures/README.md) for the seeded accounts and
[deploy/dev-tls-notes.md](deploy/dev-tls-notes.md) for real-device TLS
(Tailscale `serve` is the working setup).

### Tests

```sh
cd AmparoKit
swift test                            # hermetic — no network needed
# integration suite against the dev stack:
set -a; source ../fixtures/fixtures.env; set +a
swift test --filter AmparoAPIIntegrationTests
```

### iOS app

```sh
brew install xcodegen
cd AmparoApp && xcodegen              # generates Amparo.xcodeproj (gitignored)
```

Set `DEVELOPMENT_TEAM` in `AmparoApp/project.yml` to your own team for device
builds; the AutoFill entitlement provisions via automatic signing.

## License

[Apache-2.0](LICENSE). No GPL/AGPL code enters this repository.
