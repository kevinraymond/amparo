# TLS for device testing (P2+)

The dev stack serves plain HTTP on `localhost:8222` and, via a Caddy sidecar
with an internal CA, HTTPS on `localhost:8443` (modern Bitwarden CLI/clients
refuse plain-HTTP server URLs; trust the CA with
`NODE_EXTRA_CA_CERTS=deploy/caddy-data/caddy/pki/authorities/local/root.crt`).
That covers the Mac and the simulator. A real iPhone needs valid TLS for a
reachable hostname: iOS App Transport Security requires it, and we do not
fight ATS with exceptions — real certs from day one (handoff §5).

Two options, in order of preference:

## Option A — Tailscale HTTPS (preferred; matches production)

Matches the production deployment model (tailnet-only access).

1. Install Tailscale on the dev Mac and the test iPhone; join both to the same
   tailnet.
2. Enable HTTPS certificates for the tailnet (Tailscale admin console →
   DNS → HTTPS Certificates).
3. `tailscale cert <mac-hostname>.<tailnet>.ts.net` to mint a cert, then
   either:
   - front Vaultwarden with Caddy holding that cert (this becomes the prod
     compose shape in P5), or
   - `tailscale serve https / http://localhost:8222` to proxy directly — the
     zero-config choice for dev.
4. Set `DOMAIN=https://<mac-hostname>.<tailnet>.ts.net` in the compose env and
   point the app enrollment at that URL.

Neither Tailscale nor mkcert is installed on the build host yet; install when
device testing starts (P2/P3).

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
