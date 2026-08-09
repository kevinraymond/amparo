#!/usr/bin/env bash
# amparo dev fixtures — idempotent seed of the local Vaultwarden.
#
# 1. register-helper.mjs (node): accounts, org "Family", collection "Contas",
#    member read-only membership. Writes fixtures.env.
# 2. Official `bw` CLI: 9 org login ciphers (one with TOTP) as the caregiver,
#    1 personal login cipher as the member — vault content is produced by
#    official tooling so AmparoKit decrypts canonical data (CLEANROOM.md:
#    behavioral use of the CLI is permitted).
#
# Requires: node >= 18, `bw` (npm i -g @bitwarden/cli), stack up
# (podman compose -f deploy/compose.dev.yaml up -d).
set -euo pipefail
cd "$(dirname "$0")"

# Isolated CLI state — never touches a real Bitwarden CLI config.
export BITWARDENCLI_APPDATA_DIR="$PWD/.bw"
mkdir -p "$BITWARDENCLI_APPDATA_DIR"

# Modern `bw` refuses plain-HTTP server URLs, so it talks to the Caddy TLS
# sidecar and trusts its internal CA (see deploy/compose.dev.yaml).
VW_HTTPS_URL="${AMPARO_VW_HTTPS_URL:-https://localhost:8443}"
CADDY_ROOT_CA="$(cd .. && pwd)/deploy/caddy-data/caddy/pki/authorities/local/root.crt"
[ -f "$CADDY_ROOT_CA" ] || { echo "missing $CADDY_ROOT_CA — is the dev stack up?"; exit 1; }
export NODE_EXTRA_CA_CERTS="$CADDY_ROOT_CA"

node register-helper.mjs setup > fixtures.env
{
  echo "AMPARO_VW_HTTPS_URL=$VW_HTTPS_URL"
  echo "AMPARO_VW_CA_CERT=$CADDY_ROOT_CA"
} >> fixtures.env
# shellcheck disable=SC1091
source fixtures.env

json() { node -e "$1" "${@:2}"; }

bw_relogin() { # email password
  bw logout >/dev/null 2>&1 || true
  bw config server "$VW_HTTPS_URL" >/dev/null
  BW_SESSION=$(bw login "$1" "$2" --raw)
  export BW_SESSION
  bw sync >/dev/null
}

# Creates a login cipher unless one with the same name already exists.
# ensure_login <name> <uri> <username> <password> <totp|-> <orgId|-> <collectionId|->
ensure_login() {
  local name=$1 uri=$2 username=$3 password=$4 totp=$5 org=$6 col=$7
  if json 'const items=JSON.parse(require("fs").readFileSync(0,"utf8"));
           process.exit(items.some(i=>i.name===process.argv[1])?0:1)' "$name" < "$ITEMS_JSON"; then
    echo "  = $name (exists)"
    return
  fi
  json 'const [name,uri,username,password,totp,org,col]=process.argv.slice(1);
        process.stdout.write(Buffer.from(JSON.stringify({
          type:1, name, notes:null, favorite:false, reprompt:0,
          organizationId: org==="-"?null:org,
          collectionIds: col==="-"?[]:[col],
          login:{uris:[{match:null,uri}], username, password,
                 totp: totp==="-"?null:totp},
        })).toString("base64"))' \
    "$name" "$uri" "$username" "$password" "$totp" "$org" "$col" \
    | bw create item >/dev/null
  echo "  + $name"
}

refresh_items() { # writes current vault items to ITEMS_JSON
  ITEMS_JSON="$BITWARDENCLI_APPDATA_DIR/items.json"
  bw sync >/dev/null
  bw list items > "$ITEMS_JSON"
}

echo "== caregiver: org ciphers =="
bw_relogin "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD"
refresh_items
ensure_login "1. Banco"           "https://banco.example.com"       "maria"            "senha-banco-9481"    "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "2. Email"           "https://mail.example.com"        "maria@mail.example.com" "senha-email-2764" "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "3. Plano de Saude"  "https://saude.example.com"       "maria.silva"      "senha-saude-5130"    "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "4. Farmacia"        "https://farmacia.example.com"    "maria"            "senha-farmacia-8672" "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "5. Mercado"         "https://mercado.example.com"     "maria"            "senha-mercado-3945"  "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "6. Streaming"       "https://streaming.example.com"   "maria@mail.example.com" "senha-stream-7208" "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "7. Telefone"        "https://telefone.example.com"    "maria"            "senha-fone-1653"     "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "8. Luz"             "https://luz.example.com"         "maria.silva"      "senha-luz-4817"      "-" "$ORG_ID" "$COLLECTION_ID"
ensure_login "9. Previdencia"     "https://previdencia.example.com" "maria.silva"      "senha-prev-6039"     "JBSWY3DPEHPK3PXP" "$ORG_ID" "$COLLECTION_ID"
# Real, reachable domain with a real login form: exercises the QuickType
# suggestion path on device (M4-T3) — every *.example.com domain is fake.
ensure_login "10. Wikipedia"      "https://en.wikipedia.org"        "amparo-test"      "senha-wiki-2593"     "-" "$ORG_ID" "$COLLECTION_ID"

echo "== member: personal cipher (user-key path) =="
bw_relogin "$MEMBER_EMAIL" "$MEMBER_PASSWORD"
refresh_items
ensure_login "Portal Medico"      "https://medico.example.com"      "maria.silva"      "senha-medico-7521"   "-" "-" "-"

refresh_items
total=$(json 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")).length))' < "$ITEMS_JSON")
bw logout >/dev/null 2>&1 || true
echo "== done: member sees $total items (expect 11: 10 org + 1 personal) =="
[ "$total" -eq 11 ]
