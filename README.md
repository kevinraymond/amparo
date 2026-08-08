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
self-hosted by the caregiver, who manages everything with official Bitwarden
clients. This repo builds only the **member-side iOS client** — clean-room,
Apache-2.0.

## How it works

- The caregiver hosts Vaultwarden (Tailscale-first) and manages credentials in
  an org collection shared read-only to the member's account.
- The member's account is owned by the member (the parent). The caregiver is
  instance admin, org owner, and emergency-access grantee — that is both the
  architecture and the legal posture (see [DISCLAIMER.md](DISCLAIMER.md)).
- The amparo iOS app syncs, decrypts locally, and registers credentials with
  iOS QuickType. Most days the member never opens the app: autofill suggestion
  → Face ID → filled.
- Every error path ends in one screen: "call your caregiver", with a giant
  call button.

Full specification, phase plan, and decision log: **[docs/amparo-handoff.md](docs/amparo-handoff.md)**.

## Repository layout

```
AmparoKit/        Swift package: crypto core (AmparoCrypto) + protocol client (AmparoAPI)
AmparoApp/        Xcode project: member app + autofill extension (P2/P3)
deploy/           Dev + (later) prod compose stacks, TLS notes, runbooks
fixtures/         Dev Vaultwarden seed: test accounts, org, ciphers
docs/             Handoff spec, clean-room log
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
./fixtures/seed.sh                    # creates accounts, org, 10 test ciphers
```

See [fixtures/README.md](fixtures/README.md) for the seeded accounts and
[deploy/dev-tls-notes.md](deploy/dev-tls-notes.md) for real-device TLS.

## License

[Apache-2.0](LICENSE). No GPL/AGPL code enters this repository.
