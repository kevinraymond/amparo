# CLEAN-ROOM POLICY (hard constraint)

The iOS client must be independently authored so it can carry Apache-2.0 and
ship to the App Store without GPL entanglement.

**Prohibited inputs (never open, fetch, quote, or paraphrase-from):**
- Source of any Bitwarden client repo (`bitwarden/ios`, `bitwarden/android`,
  `bitwarden/clients`, `bitwarden/mobile`, `bitwarden/sdk*`) — GPL-3.0.
- Source of any third-party Bitwarden-compatible client (rbw, goldwarden,
  Keyguard, etc.) regardless of license — avoids taint arguments entirely.
- Vaultwarden **source code** (AGPL). Its **wiki/docs** are fine.

**Permitted inputs:**
- Bitwarden Security Whitepaper and help.bitwarden.com (documentation, not
  code).
- Vaultwarden wiki.
- Observed HTTP behavior of our own Vaultwarden instance (black-box traffic
  via mitmproxy against official clients is acceptable behavioral
  observation).
- Test vectors generated **behaviorally** with the official Bitwarden CLI
  (running a tool ≠ copying source).
- Apple documentation; RFCs (2898 PBKDF2, 5869 HKDF, 8018).
- The project handoff document (`docs/amparo-handoff.md`; its §6 spec was
  written from documentation, not source).

**Process:** if ever uncertain whether an input is permitted, stop and ask.
Log every external reference consulted in `docs/cleanroom-log.md` (URL, date,
what was taken). Interfaces/wire formats are not copyrightable; expression is
— we re-derive all expression.
