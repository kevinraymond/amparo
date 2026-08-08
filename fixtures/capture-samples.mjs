#!/usr/bin/env node
// amparo fixtures — raw API response samples for AmparoAPI tests (M2).
//
// Black-box behavioral capture against our own dev Vaultwarden (CLEANROOM.md:
// permitted). Snapshots the exact HTTP bodies the Swift decoder and error
// mapper must handle, so unit tests run offline against real server output.
//
// Output: AmparoKit/Tests/AmparoAPITests/Resources/*.json, each enveloped as
//   { captured, request, status, body }
// Re-run after re-seeding: node capture-samples.mjs
// (sync-success.json covaries with e2e-vectors.json — regenerate together.)
//
// The 2FA sample uses a dedicated throwaway account (twofa-sample@amparo.test)
// that is created once and *kept* with authenticator 2FA enabled: re-runs then
// capture the challenge body with a single login attempt. It never touches the
// member/caregiver fixtures or seed.sh's 10-item assertion.
//
// These are throwaway dev fixtures; committing tokens/key material is intended.

import crypto from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import {
  masterKey, masterPasswordHash, stretchMasterKey, splitKey, encString2, newRsaPair,
} from './vw-crypto.mjs';

const VW_URL = process.env.VW_URL ?? 'http://localhost:8222';
const KDF_ITERATIONS = 600_000;
const MEMBER = {
  email: (process.env.MEMBER_EMAIL ?? 'member@amparo.test').toLowerCase(),
  password: process.env.MEMBER_PASSWORD ?? 'Fixture-Member-2026-Hx7q',
};
const TWOFA = {
  email: 'twofa-sample@amparo.test',
  password: 'Fixture-TwoFA-2026-Vq3n',
  name: 'Dev 2FA Sample',
};
const OUT_DIR = path.resolve('../AmparoKit/Tests/AmparoAPITests/Resources');

const b64url = (s) => Buffer.from(s, 'utf8').toString('base64url');
const field = (obj, name) => obj?.[name] ?? obj?.[name[0].toUpperCase() + name.slice(1)];

async function api(method, urlPath, { token, json, form } = {}) {
  const headers = {};
  let body;
  if (json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
  if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (form?.username) headers['Auth-Email'] = b64url(form.username);
  const res = await fetch(`${VW_URL}${urlPath}`, { method, headers, body });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

const deviceId = (email) => {
  const h = crypto.createHash('sha256').update(`amparo-fixtures:${email}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};

const passwordGrant = (email, hash) =>
  api('POST', '/identity/connect/token', {
    form: {
      grant_type: 'password', scope: 'api offline_access', client_id: 'mobile',
      username: email, password: hash,
      deviceType: '1', deviceIdentifier: deviceId(email), deviceName: 'amparo-samples',
    },
  });

const samples = {};
const record = (name, request, resp) => {
  samples[name] = {
    captured: new Date().toISOString().slice(0, 10),
    request,
    status: resp.status,
    body: resp.data,
  };
  console.error(`${name}: HTTP ${resp.status}`);
};

// --- member happy paths + error bodies -------------------------------------

const pre = await api('POST', '/identity/accounts/prelogin', { json: { email: MEMBER.email } });
if (!pre.ok) throw new Error(`prelogin failed (HTTP ${pre.status}) — is the dev stack up and seeded?`);
record('prelogin', 'POST /identity/accounts/prelogin (member)', pre);

const iterations = field(pre.data, 'kdfIterations') ?? KDF_ITERATIONS;
const mk = masterKey(MEMBER.email, MEMBER.password, iterations);
const token = await passwordGrant(MEMBER.email, masterPasswordHash(mk, MEMBER.password));
if (!token.ok) throw new Error(`member login failed (HTTP ${token.status})`);
record('token-success', 'POST /identity/connect/token (password grant, member)', token);

const sync = await api('GET', '/api/sync?excludeDomains=true', {
  token: field(token.data, 'accessToken') ?? token.data.access_token,
});
if (!sync.ok) throw new Error(`sync failed (HTTP ${sync.status})`);
record('sync-success', 'GET /api/sync?excludeDomains=true (member)', sync);

const wrongMk = masterKey(MEMBER.email, 'not-the-password', iterations);
record('token-wrong-password', 'POST /identity/connect/token (password grant, wrong password)',
  await passwordGrant(MEMBER.email, masterPasswordHash(wrongMk, 'not-the-password')));

record('token-refresh-invalid', 'POST /identity/connect/token (refresh grant, garbage token)',
  await api('POST', '/identity/connect/token', {
    form: { grant_type: 'refresh_token', client_id: 'mobile', refresh_token: 'garbage-refresh-token' },
  }));

// --- 2FA challenge body -----------------------------------------------------
// RFC 6238 TOTP (SHA-1, 30 s, 6 digits) from the base32 key the server hands out.

const b32decode = (s) => {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0, value = 0;
  const out = [];
  for (const c of s.toUpperCase().replace(/=+$/, '')) {
    const idx = alphabet.indexOf(c);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(out);
};

const totp = (keyB32) => {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 1000 / 30)));
  const h = crypto.createHmac('sha1', b32decode(keyB32)).update(counter).digest();
  const off = h[h.length - 1] & 0x0f;
  return ((h.readUInt32BE(off) & 0x7fffffff) % 1_000_000).toString().padStart(6, '0');
};

async function registerAccount({ email, password, name }) {
  const accMk = masterKey(email, password, KDF_ITERATIONS);
  const userKey = crypto.randomBytes(64);
  const { publicDer, privateDer } = newRsaPair();
  const payload = {
    email, name,
    masterPasswordHash: masterPasswordHash(accMk, password),
    masterPasswordHint: null,
    key: encString2(stretchMasterKey(accMk), userKey),
    keys: {
      publicKey: publicDer.toString('base64'),
      encryptedPrivateKey: encString2(splitKey(userKey), privateDer),
    },
    kdf: 0,
    kdfIterations: KDF_ITERATIONS,
  };
  let reg = await api('POST', '/identity/accounts/register', { json: payload });
  if (reg.status === 404 || reg.status === 405 || reg.status === 410) {
    const send = await api('POST', '/identity/accounts/register/send-verification-email', {
      json: { email, name, receiveMarketingEmails: false },
    });
    if (!send.ok) throw new Error(`register/send-verification-email: HTTP ${send.status}`);
    const vtoken = typeof send.data === 'string' ? send.data : send.data.raw ?? field(send.data, 'token');
    reg = await api('POST', '/identity/accounts/register/finish', {
      json: {
        email, emailVerificationToken: vtoken,
        masterPasswordHash: payload.masterPasswordHash,
        masterPasswordHint: null,
        userSymmetricKey: payload.key,
        userAsymmetricKeys: payload.keys,
        kdf: 0, kdfIterations: KDF_ITERATIONS,
      },
    });
  }
  if (!reg.ok) throw new Error(`register ${email}: HTTP ${reg.status} ${JSON.stringify(reg.data).slice(0, 300)}`);
}

async function capture2fa() {
  const hash = masterPasswordHash(masterKey(TWOFA.email, TWOFA.password, KDF_ITERATIONS), TWOFA.password);
  let attempt = await passwordGrant(TWOFA.email, hash);
  if (attempt.ok) {
    // Account exists but 2FA is off (partial earlier run) — enable it now.
    const access = field(attempt.data, 'accessToken') ?? attempt.data.access_token;
    const get = await api('POST', '/api/two-factor/get-authenticator', {
      token: access, json: { masterPasswordHash: hash },
    });
    if (!get.ok) throw new Error(`get-authenticator: HTTP ${get.status} ${JSON.stringify(get.data).slice(0, 300)}`);
    const key = field(get.data, 'key');
    let enable = await api('PUT', '/api/two-factor/authenticator', {
      token: access, json: { key, token: totp(key), masterPasswordHash: hash },
    });
    if (enable.status === 404 || enable.status === 405) {
      enable = await api('POST', '/api/two-factor/authenticator', {
        token: access, json: { key, token: totp(key), masterPasswordHash: hash },
      });
    }
    if (!enable.ok) throw new Error(`enable authenticator: HTTP ${enable.status} ${JSON.stringify(enable.data).slice(0, 300)}`);
    attempt = await passwordGrant(TWOFA.email, hash);
  } else if (attempt.status === 400 || attempt.status === 401) {
    const bodyText = JSON.stringify(attempt.data);
    if (!/twofactor/i.test(bodyText)) {
      // Not a 2FA challenge → account doesn't exist yet. Register, then recurse once.
      await registerAccount(TWOFA);
      return capture2fa();
    }
  }
  if (attempt.ok || !/twofactor/i.test(JSON.stringify(attempt.data))) {
    throw new Error(`expected a 2FA challenge, got HTTP ${attempt.status} ${JSON.stringify(attempt.data).slice(0, 300)}`);
  }
  record('token-2fa', 'POST /identity/connect/token (password grant, authenticator 2FA enabled)', attempt);
}

try {
  await capture2fa();
} catch (err) {
  console.error(`WARNING: 2FA capture failed — ${err.message}`);
  console.error('Shipping without token-2fa.json; Swift falls back to provisional TwoFactorProviders detection (D14).');
}

// --- write ------------------------------------------------------------------

mkdirSync(OUT_DIR, { recursive: true });
for (const [name, sample] of Object.entries(samples)) {
  const file = path.join(OUT_DIR, `${name}.json`);
  writeFileSync(file, JSON.stringify(sample, null, 2) + '\n');
}
console.log(`wrote ${Object.keys(samples).length} samples to ${OUT_DIR}`);
