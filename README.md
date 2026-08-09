# amparo

> Unofficial project. Compatible with the Bitwarden® server API; **not
> affiliated with, endorsed by, or supported by Bitwarden, Inc.** See
> [TRADEMARKS.md](TRADEMARKS.md) and [DISCLAIMER.md](DISCLAIMER.md).

An open-source, free system that lets a tech-savvy adult child (the
**caregiver**) remotely manage credentials for an elderly parent (the
**member**), who gets a dead-simple, big-button, biometric-only iOS
experience — one tap to fill a password, zero jargon, zero master-password
prompts after enrollment. Works inside iOS **Assistive Access**.

Amparo (pt-BR: support, protection) is **not** a new password manager. The
backend is stock [Vaultwarden](https://github.com/dani-garcia/vaultwarden),
self-hosted by the caregiver (the reference, Tailscale-first deployment) —
cloud Bitwarden support for caregivers who won't self-host is landing next
(spec §2.1, M4.5). The caregiver manages everything with official Bitwarden
clients. This repo builds only the **member-side iOS client** — clean-room,
Apache-2.0.

<!-- TODO: screenshots — home grid, detail screen, QuickType fill, call-caregiver screen -->

## Why this exists

Amparo began as [a request on r/SomebodyMakeThis](https://www.reddit.com/r/SomebodyMakeThis/comments/1vit5w3/an_app_where_adult_kids_manage_their_elderly/) —
an app where adult kids manage their elderly parents' passwords. This is
that app.

If your parent can handle a stock password manager with biometrics, use one —
the family-vault features in Bitwarden, 1Password, and Apple Passwords are
genuinely good, and Amparo is not for you.

Where stock apps break down is the last inch of UX for a cognitively
impaired or deeply non-technical user: autofill that works most of the time
(and the rest is a support call), app updates that quietly rearrange the UI,
vault-timeout reprompts for a master password they never knew, and error
dialogs that dead-end someone who can't troubleshoot. Those aren't storage or
sync problems — they're interaction-surface problems, and they can't be fixed
from inside a general-purpose client.

Amparo replaces only that layer. The member surface is deliberately frozen
and minimal: Face ID is the only unlock, autofill is the primary path, the
in-app fallback is a big-tile grid, and every error state collapses to one
screen — "call your caregiver," with a giant call button. No settings, no
onboarding, no password-manager vocabulary anywhere.

Self-hosting also answers a trust objection common in this generation ("the
password company will see my passwords"): no company holds anything. The
vault lives on hardware the family controls, and the crypto is Bitwarden's
zero-knowledge model unchanged.

## Is amparo right for your family?

**Good fit:** a parent who can tap a Face ID prompt but is defeated by
anything more; a caregiver comfortable running a Docker container and a
tailnet (or, post-M4.5, a cloud Bitwarden account); iPhone on the member
side.

**Not the tool:** parents who manage a stock app fine today (use the stock
app); families needing Android on the member side (deferred); anyone wanting
a hosted service — Amparo is software, not a service, and the authors run
nothing and hold nothing. Use of Amparo requires the member's informed,
ongoing consent; see [DISCLAIMER.md](DISCLAIMER.md).

## How it works

- The caregiver hosts Vaultwarden (or, post-M4.5, uses cloud Bitwarden) and
  manages credentials in an org collection shared read-only to the member's
  account.
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

## Security model (summary)

- Zero-knowledge, unchanged from Bitwarden's documented model: the master
  password never leaves the device; keys are derived locally (PBKDF2-SHA256,
  600k) and used to decrypt the account's symmetric key.
- Decryption keys live in the iOS Keychain protected by
  `SecAccessControl(.biometryCurrentSet)` — every read is a Face ID prompt,
  and re-enrolling Face ID invalidates them (caregiver re-enrolls).
- Ciphers are cached **as received, still encrypted**; fields decrypt on
  demand. Clipboard copies expire; revealed passwords auto-hide.
- Clean-room implementation from public documentation and observed protocol
  behavior only — see [CLEANROOM.md](CLEANROOM.md) and
  `docs/cleanroom-log.md`.

## Status (2026-08)

Working end-to-end on a real device: enrollment → sync → member UI →
AutoFill in Safari and third-party apps — **including inside Assistive
Access** (D21). Apple does not document third-party credential providers as
supported in Assistive Access; amparo is verified working there on-device.

| Milestone | State |
|---|---|
| M0 scaffold/dev stack · M1 crypto core · M2 protocol client · M3 member app · M4 autofill extension | ✅ complete |
| M4.5 backend-agnostic auth — cloud Bitwarden presets + unified API-key flow (D22/D23) | next |
| M5 pilot/hardening — TestFlight, colorblind themes, one-time-code autofill | pending |
| M6 caregiver deployment kit — prod compose, runbooks, backup | pending |
| Android client | deferred (no test device) |

Session-by-session detail: [docs/STATUS.md](docs/STATUS.md).

## Installing

There is no App Store or TestFlight build yet (that's M5). Until then, the
caregiver builds from source: a Mac with Xcode, a paid Apple Developer
membership (required for the AutoFill entitlement on-device), and the steps
under [iOS app](#ios-app) below. This is a real constraint, on purpose — the
project would rather ship to early adopters who can build it than run a
service.

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
cd AmparoApp && ./generate.sh         # generates Amparo.xcodeproj (gitignored)
```

Simulator builds work out of the box. For device builds, put your Apple
team ID in `AmparoApp/project-local.yml` (created from the example on first
run, gitignored) and change the bundle identifiers + app-group values in
`project.yml` to your own reverse-DNS root — app groups are team-scoped, so
the defaults can't be reused. The code derives everything else from the
bundle id at runtime; the AutoFill entitlement provisions via automatic
signing.

## License

[Apache-2.0](LICENSE). No GPL/AGPL code enters this repository.
