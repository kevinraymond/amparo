# amparo — project instructions for Claude Code

Single source of truth: `docs/amparo-handoff.md`. Read it before nontrivial
work. Append decisions to its Decision Log (§12) in the same commit as the
work that decided them.

## Clean-room policy (HARD CONSTRAINT — full text in CLEANROOM.md)

The iOS client must be independently authored: Apache-2.0, App Store, no GPL
entanglement.

**Never open, fetch, quote, or paraphrase from:** any Bitwarden client source
(`bitwarden/ios`, `bitwarden/android`, `bitwarden/clients`,
`bitwarden/mobile`, `bitwarden/sdk*` — GPL-3.0); any third-party
Bitwarden-compatible client source (rbw, goldwarden, Keyguard, …) regardless
of license; Vaultwarden **source code** (AGPL). This includes search results —
do not follow links into these repos.

**Permitted:** Bitwarden Security Whitepaper and help.bitwarden.com;
Vaultwarden wiki; black-box observed HTTP behavior of our own Vaultwarden
instance; test vectors generated behaviorally with the official `bw` CLI;
Apple docs; RFCs (2898, 5869, 8018); the handoff document.

**Process:** uncertain whether an input is permitted → stop and ask. Log every
external reference consulted in `docs/cleanroom-log.md` (URL, date, what was
taken). When protocol behavior is ambiguous, test against the local
Vaultwarden and document the observed behavior.

## Product principles (member = elderly parent; caregiver = their adult child)

1. **Member never sees** password-manager vocabulary: vault, folder,
   collection, URI, TOTP, KDF, sync, master password — none of it, anywhere in
   member UI.
2. **Autofill is the product.** The app UI is the fallback: QuickType
   suggestion → Face ID → filled.
3. **Parent owns the account.** Caregiver is instance admin + org owner +
   emergency-access grantee. Architecture and legal posture.
4. **Fail to a human.** Every error state terminates in one screen: "Something
   needs attention — call {caregiver}" with a giant call button. No retry
   dialogs, no error codes, no raw error text.
5. **Local-first.** Works offline from last sync. No third-party cloud.
   Tailscale-first deployment.

## Session discipline

- One milestone (§11) per session where possible. Run tests before ending a
  session. Update Decision Log + cleanroom log in the same commit.
- Licensing: everything in this repo is Apache-2.0. No GPL/AGPL code enters
  this repo, ever.
- Dev stack runs under **podman** (`podman compose -f deploy/compose.dev.yaml
  up -d`), not Docker Desktop. Vaultwarden dev instance:
  `http://localhost:8222`; fixtures in `fixtures/` (see its README).
