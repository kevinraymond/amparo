#!/usr/bin/env node
// amparo fixtures — behavioral test-vector capture for AmparoKit (M1-T5).
//
// Logs into the dev Vaultwarden as the member, captures the raw protected
// keys and cipher EncStrings from the live API, computes every §6
// intermediate with fixtures/vw-crypto.mjs, and takes expected plaintexts
// from the official `bw` CLI so the Swift tests are validated against
// official-tooling output (CLEANROOM.md: behavioral use is permitted).
//
// Output: AmparoKit/Tests/AmparoCryptoTests/Resources/e2e-vectors.json
// Re-run after re-seeding: node gen-vectors.mjs
//
// These are throwaway dev fixtures; committing the key material is intended.

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import {
  masterKey, masterPasswordHash, stretchMasterKey, splitKey, decString2, rsaUnwrap,
} from './vw-crypto.mjs';

const VW_URL = process.env.VW_URL ?? 'http://localhost:8222';
const VW_HTTPS_URL = process.env.AMPARO_VW_HTTPS_URL ?? 'https://localhost:8443';
const EMAIL = (process.env.MEMBER_EMAIL ?? 'member@amparo.test').toLowerCase();
const PASSWORD = process.env.MEMBER_PASSWORD ?? 'Fixture-Member-2026-Hx7q';
const VECTOR_CIPHERS = ['1. Bank', '9. Retirement', 'Medical Portal'];
const OUT = path.resolve('../AmparoKit/Tests/AmparoCryptoTests/Resources/e2e-vectors.json');

const field = (obj, name) => obj?.[name] ?? obj?.[name[0].toUpperCase() + name.slice(1)];

async function api(method, urlPath, { token, json, form } = {}) {
  const headers = {};
  let body;
  if (json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
  if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (form?.username) headers['Auth-Email'] = Buffer.from(form.username, 'utf8').toString('base64url');
  const res = await fetch(`${VW_URL}${urlPath}`, { method, headers, body });
  if (!res.ok) throw new Error(`${method} ${urlPath}: HTTP ${res.status} ${await res.text()}`);
  return res.json();
}

// --- login as member, capture protected keys -------------------------------

const pre = await api('POST', '/identity/accounts/prelogin', { json: { email: EMAIL } });
const iterations = field(pre, 'kdfIterations');
const mk = masterKey(EMAIL, PASSWORD, iterations);
const stretched = stretchMasterKey(mk);
const token = await api('POST', '/identity/connect/token', {
  form: {
    grant_type: 'password', scope: 'api offline_access', client_id: 'mobile',
    username: EMAIL, password: masterPasswordHash(mk, PASSWORD),
    deviceType: '1', deviceIdentifier: '78dd403f-ee42-4f26-8b5e-2ba1e2ed65b7', deviceName: 'amparo-vectors',
  },
});
const protectedUserKey = field(token, 'key');
const encryptedPrivateKey = field(token, 'privateKey');
const userKey = decString2(stretched, protectedUserKey);
const privateDer = decString2(splitKey(userKey), encryptedPrivateKey);

const sync = await api('GET', '/api/sync?excludeDomains=true', { token: field(token, 'accessToken') ?? token.access_token });
const org = (field(field(sync, 'profile'), 'organizations') ?? [])[0];
const orgKeyEnc = field(org, 'key');
const orgKey = rsaUnwrap(privateDer, orgKeyEnc);

// --- expected plaintexts from official bw ----------------------------------

const bwEnv = {
  ...process.env,
  BITWARDENCLI_APPDATA_DIR: path.resolve('.bw'),
  NODE_EXTRA_CA_CERTS: path.resolve('../deploy/caddy-data/caddy/pki/authorities/local/root.crt'),
};
const bw = (args, input) =>
  execFileSync('bw', args, { env: bwEnv, input, encoding: 'utf8' }).trim();
try { bw(['logout']); } catch { /* not logged in */ }
bw(['config', 'server', VW_HTTPS_URL]);
const session = bw(['login', EMAIL, PASSWORD, '--raw']);
bw(['sync', '--session', session]);
const items = JSON.parse(bw(['list', 'items', '--session', session]));
bw(['logout']);

// --- assemble vectors ------------------------------------------------------

// Raw (encrypted) cipher fields come from the sync payload; expected
// plaintexts come from bw. Match records by decrypting nothing ourselves —
// pair org ciphers via organizationId + bw id.
const syncCiphers = field(sync, 'ciphers') ?? [];
const ciphers = VECTOR_CIPHERS.map((expectedName) => {
  const plain = items.find((i) => i.name === expectedName);
  if (!plain) throw new Error(`bw has no item named ${expectedName} — re-run seed.sh`);
  const raw = syncCiphers.find((c) => field(c, 'id') === plain.id);
  if (!raw) throw new Error(`sync payload missing cipher ${plain.id}`);
  const rawLogin = field(raw, 'login');
  const uri = (field(rawLogin, 'uris') ?? [])[0];
  return {
    id: plain.id,
    organizationId: field(raw, 'organizationId') ?? null,
    name: { enc: field(raw, 'name'), expected: plain.name },
    username: { enc: field(rawLogin, 'username'), expected: plain.login.username },
    password: { enc: field(rawLogin, 'password'), expected: plain.login.password },
    uri: { enc: field(uri, 'uri'), expected: plain.login.uris[0].uri },
    totp: plain.login.totp ? { enc: field(rawLogin, 'totp'), expected: plain.login.totp } : null,
  };
});

const vectors = {
  generated: '2026-08-08',
  source: 'fixtures/gen-vectors.mjs — behavioral capture: dev Vaultwarden API + official bw CLI output',
  account: {
    email: EMAIL,
    password: PASSWORD,
    kdf: 0,
    kdfIterations: iterations,
    masterKeyHex: mk.toString('hex'),
    masterPasswordHashB64: masterPasswordHash(mk, PASSWORD),
    stretchedEncKeyHex: stretched.enc.toString('hex'),
    stretchedMacKeyHex: stretched.mac.toString('hex'),
    protectedUserKey,
    userKeyHex: userKey.toString('hex'),
    encryptedPrivateKey,
    privateKeyPkcs8B64: privateDer.toString('base64'),
  },
  organization: {
    id: field(org, 'id'),
    encKey: orgKeyEnc,
    orgKeyHex: orgKey.toString('hex'),
  },
  ciphers,
};

mkdirSync(path.dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(vectors, null, 2) + '\n');
console.log(`wrote ${OUT}: ${ciphers.length} ciphers (${ciphers.map((c) => c.name.expected).join(', ')})`);
