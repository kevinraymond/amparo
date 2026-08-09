# Screenshots for the README (fixture data only — never real credentials)

Take on the test device (fixture vault), portrait, light mode. Capture
**on-device** (side button + volume up), not via iPhone Mirroring — Mirroring
requires the phone locked, and Face ID can't fire from a mirrored session, so
Amparo can't unlock there. Drop the PNGs in this directory and wire them into
README.md where the TODO comment sits.

| File | Shot |
|---|---|
| `home-grid.png` | Member home: 11 big tiles, Bank first |
| `detail-totp.png` | Retirement detail: giant copy button + 64pt TOTP ring |
| `quicktype-fill.png` | Safari on the Wikipedia sign-in (lands on auth.wikimedia.org) with the inline `amparo-test` QuickType chip or mid-fill |
| `call-caregiver.png` | The "Something needs attention" screen (stage: caregiver settings → "Preview member help screen"; exit = 5s hold on the headline) |

Suggested README block once files exist:

```markdown
| | | | |
|---|---|---|---|
| ![Home](docs/screenshots/home-grid.png) | ![Detail](docs/screenshots/detail-totp.png) | ![AutoFill](docs/screenshots/quicktype-fill.png) | ![Help](docs/screenshots/call-caregiver.png) |
```
