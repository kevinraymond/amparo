# TLS for device testing (P2+)

The dev stack serves plain HTTP on `localhost:8222` and, via a Caddy sidecar
with an internal CA, HTTPS on `localhost:8443` (modern Bitwarden CLI/clients
refuse plain-HTTP server URLs; trust the CA with
`NODE_EXTRA_CA_CERTS=deploy/caddy-data/caddy/pki/authorities/local/root.crt`).
That covers the Mac and the simulator. A real iPhone needs valid TLS for a
reachable hostname: iOS App Transport Security requires it, and we do not
fight ATS with exceptions — real certs from day one (handoff §5).

Two options, in order of preference:

## Option A — Tailscale HTTPS (preferred; matches production) — LIVE since 2026-08-08

Matches the production deployment model (tailnet-only access).

**Current dev setup (working):**

- Mac app installed via `brew install --cask tailscale-app`; CLI at
  `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. Node renamed
  a memorable name via `tailscale set --hostname <node>`. The test iPhone on
  the same tailnet.
- HTTPS certificates enabled tailnet-wide (admin console → DNS →
  HTTPS Certificates). Without this, `tailscale serve` hangs on an
  interactive enable prompt and `tailscale cert` returns
  "account does not support getting TLS certs".
- Proxy: `tailscale serve --bg http://localhost:8222` — serves
  **`https://<node>.<tailnet>.ts.net`** (tailnet-only) with a real
  Let's Encrypt cert, auto-renewed by tailscaled; config persists across
  restarts. Disable with `tailscale serve --https=443 off`.
- Verified: `/alive` 200 and prelogin through the proxy; cert chain is
  publicly trusted, so iOS ATS accepts it with zero device configuration.

**Enrollment URL for device testing: `https://<node>.<tailnet>.ts.net`** (operator values live in gitignored `deploy/dev-local.md`)

Caveat: compose still sets `DOMAIN=https://localhost:8443`. That base URL
only leaks into web-vault links and invite emails (unused in dev); every
mobile-API flow the app touches is DOMAIN-agnostic. The P5 prod compose sets
DOMAIN to the tailnet URL properly.

## Option B — mkcert on the LAN

1. `brew install mkcert && mkcert -install` on the Mac.
2. Pick a LAN hostname for the Mac (e.g. `vw.local.test` via the device's
   configured DNS, or the Mac's `.local` name), `mkcert <hostname>`.
3. Install the mkcert root CA on the iPhone: AirDrop the root CA file, then
   Settings → General → VPN & Device Management (install profile) → Settings →
   General → About → Certificate Trust Settings → enable full trust.
4. Front Vaultwarden with Caddy using the minted cert; set `DOMAIN`
   accordingly.

Option B works fully offline but adds a trusted root to the test device;
prefer A unless the tailnet is unavailable.
