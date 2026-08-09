#!/usr/bin/env node
// amparo fixtures — account/org bootstrap for the local dev Vaultwarden.
//
// Implements the key derivation and EncString formats from
// docs/amparo-handoff.md §6 (written from public documentation; see
// CLEANROOM.md) using Node stdlib only, and drives the server's HTTP API as
// observed behaviorally against our own instance. Dev tooling only — this is
// NOT the clean-room iOS implementation, but its derivations double as
// behavioral test vectors for AmparoKit (handoff §9).
//
// The official `bw` CLI cannot register accounts or create organizations
// (those flows run client-side in the web vault), hence this helper.
// Cipher seeding stays in seed.sh via `bw` so vault content is produced by
// official tooling.
//
// Usage: node register-helper.mjs setup   (idempotent; prints KEY=VALUE lines)
// Config via env: VW_URL, CAREGIVER_EMAIL/PASSWORD/NAME, MEMBER_EMAIL/PASSWORD/NAME

import crypto from 'node:crypto';
import {
  masterKey, masterPasswordHash, stretchMasterKey, splitKey,
  encString2, decString2, rsaWrap4, rsaUnwrap, newRsaPair, ownPublicDer,
} from './vw-crypto.mjs';

const VW_URL = process.env.VW_URL ?? 'http://localhost:8222';
const KDF_ITERATIONS = 600_000; // handoff D3: member accounts pinned PBKDF2 600k

const CAREGIVER = {
  email: (process.env.CAREGIVER_EMAIL ?? 'caregiver@amparo.test').toLowerCase(),
  password: process.env.CAREGIVER_PASSWORD ?? 'Fixture-Caregiver-2026-9m2K',
  name: process.env.CAREGIVER_NAME ?? 'Dev Caregiver',
};
const MEMBER = {
  email: (process.env.MEMBER_EMAIL ?? 'member@amparo.test').toLowerCase(),
  password: process.env.MEMBER_PASSWORD ?? 'Fixture-Member-2026-Hx7q',
  name: process.env.MEMBER_NAME ?? 'Dev Member',
};
const ORG_NAME = 'Family';
const COLLECTION_NAME = 'Accounts';

// ------------------------------------------------------------------- HTTP

const b64url = (s) => Buffer.from(s, 'utf8').toString('base64url');
// Tolerant field access: server JSON casing varies across versions.
const field = (obj, name) => obj?.[name] ?? obj?.[name[0].toUpperCase() + name.slice(1)];

async function api(method, path, { token, json, form } = {}) {
  const headers = {};
  let body;
  if (json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
  if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (form?.username) headers['Auth-Email'] = b64url(form.username);
  const res = await fetch(`${VW_URL}${path}`, { method, headers, body });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

const fail = (msg, resp) => {
  throw new Error(`${msg}: HTTP ${resp.status} ${JSON.stringify(resp.data).slice(0, 500)}`);
};

// ------------------------------------------------------------------- flows

// Stable per-email device id so re-runs don't accumulate devices server-side.
const deviceId = (email) => {
  const h = crypto.createHash('sha256').update(`amparo-fixtures:${email}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};

// §6.3 ROPC login. Returns tokens + protected keys + derived key material.
async function login({ email, password }) {
  const pre = await api('POST', '/identity/accounts/prelogin', { json: { email } });
  if (!pre.ok) fail(`prelogin ${email}`, pre);
  const kdf = field(pre.data, 'kdf') ?? 0;
  const iterations = field(pre.data, 'kdfIterations') ?? KDF_ITERATIONS;
  if (kdf !== 0) throw new Error(`fixture accounts must be PBKDF2 (kdf=0), got kdf=${kdf}`);
  const mk = masterKey(email, password, iterations);
  const resp = await api('POST', '/identity/connect/token', {
    form: {
      grant_type: 'password',
      scope: 'api offline_access',
      client_id: 'mobile',
      username: email,
      password: masterPasswordHash(mk, password),
      deviceType: '1',
      deviceIdentifier: deviceId(email),
      deviceName: 'amparo-fixtures',
    },
  });
  return resp.ok ? { ok: true, resp } : { ok: false, resp };
}

async function loginFull(account) {
  const r = await login(account);
  if (!r.ok) return r;
  const data = r.resp.data;
  const mk = masterKey(account.email, account.password, field(data, 'kdfIterations') ?? KDF_ITERATIONS);
  const userKey = decString2(stretchMasterKey(mk), field(data, 'key'));
  const privateDer = decString2(splitKey(userKey), field(data, 'privateKey'));
  return { ok: true, token: field(data, 'accessToken') ?? data.access_token, userKey, privateDer };
}

async function ensureAccount(account) {
  const existing = await loginFull(account);
  if (existing.ok) return { ...existing, created: false };

  const mk = masterKey(account.email, account.password, KDF_ITERATIONS);
  const userKey = crypto.randomBytes(64);
  const { publicDer, privateDer } = newRsaPair();
  const payload = {
    email: account.email,
    name: account.name,
    masterPasswordHash: masterPasswordHash(mk, account.password),
    masterPasswordHint: null,
    key: encString2(stretchMasterKey(mk), userKey),
    keys: {
      publicKey: publicDer.toString('base64'),
      encryptedPrivateKey: encString2(splitKey(userKey), privateDer),
    },
    kdf: 0,
    kdfIterations: KDF_ITERATIONS,
  };
  let reg = await api('POST', '/identity/accounts/register', { json: payload });
  if (reg.status === 404 || reg.status === 405 || reg.status === 410) {
    // Newer registration flow: verification email token, returned directly
    // when SMTP is disabled, then a "finish" call.
    const send = await api('POST', '/identity/accounts/register/send-verification-email', {
      json: { email: account.email, name: account.name, receiveMarketingEmails: false },
    });
    if (!send.ok) fail(`register/send-verification-email ${account.email}`, send);
    const token = typeof send.data === 'string' ? send.data : send.data.raw ?? field(send.data, 'token');
    reg = await api('POST', '/identity/accounts/register/finish', {
      json: {
        email: account.email,
        emailVerificationToken: token,
        masterPasswordHash: payload.masterPasswordHash,
        masterPasswordHint: null,
        userSymmetricKey: payload.key,
        userAsymmetricKeys: payload.keys,
        kdf: 0,
        kdfIterations: KDF_ITERATIONS,
      },
    });
  }
  if (!reg.ok) fail(`register ${account.email}`, reg);
  const after = await loginFull(account);
  if (!after.ok) fail(`post-register login ${account.email}`, after.resp);
  return { ...after, created: true };
}

async function sync(token) {
  const r = await api('GET', '/api/sync?excludeDomains=true', { token });
  if (!r.ok) fail('sync', r);
  return r.data;
}

async function ensureOrg(cg) {
  const profile = field(await sync(cg.token), 'profile');
  const orgs = field(profile, 'organizations') ?? [];
  const existing = orgs.find((o) => field(o, 'name') === ORG_NAME);
  let orgId, orgKey;
  if (existing) {
    orgId = field(existing, 'id');
    orgKey = rsaUnwrap(cg.privateDer, field(existing, 'key'));
  } else {
    orgKey = crypto.randomBytes(64);
    const orgPair = newRsaPair();
    const create = await api('POST', '/api/organizations', {
      token: cg.token,
      json: {
        name: ORG_NAME,
        billingEmail: CAREGIVER.email,
        planType: 0, // Free
        key: rsaWrap4(ownPublicDer(cg.privateDer), orgKey),
        collectionName: encString2(splitKey(orgKey), Buffer.from(COLLECTION_NAME, 'utf8')),
        keys: {
          publicKey: orgPair.publicDer.toString('base64'),
          encryptedPrivateKey: encString2(splitKey(orgKey), orgPair.privateDer),
        },
      },
    });
    if (!create.ok) fail('create organization', create);
    orgId = field(create.data, 'id');
  }
  const cols = await api('GET', `/api/organizations/${orgId}/collections`, { token: cg.token });
  if (!cols.ok) fail('list collections', cols);
  const colList = field(cols.data, 'data') ?? cols.data;
  const collection = colList.find((c) => {
    try { return decString2(splitKey(orgKey), field(c, 'name')).toString('utf8') === COLLECTION_NAME; }
    catch { return false; }
  }) ?? colList[0];
  return { orgId, orgKey, collectionId: field(collection, 'id') };
}

async function ensureMembership(cg, org, memberEmail) {
  const list = await api('GET', `/api/organizations/${org.orgId}/users`, { token: cg.token });
  if (!list.ok) fail('list org users', list);
  let entry = (field(list.data, 'data') ?? []).find(
    (u) => (field(u, 'email') ?? '').toLowerCase() === memberEmail,
  );
  if (!entry) {
    // Read-only + passwords visible (§2: read-only + view).
    const invite = await api('POST', `/api/organizations/${org.orgId}/users/invite`, {
      token: cg.token,
      json: {
        emails: [memberEmail],
        type: 2, // User
        accessAll: false,
        collections: [{ id: org.collectionId, readOnly: true, hidePasswords: false, manage: false }],
        groups: [],
      },
    });
    if (!invite.ok) fail('invite member', invite);
    const relist = await api('GET', `/api/organizations/${org.orgId}/users`, { token: cg.token });
    entry = (field(relist.data, 'data') ?? []).find(
      (u) => (field(u, 'email') ?? '').toLowerCase() === memberEmail,
    );
  }
  if (!entry) throw new Error('member not present in org after invite');
  const orgUserId = field(entry, 'id');
  const status = field(entry, 'status'); // 0 invited, 1 accepted, 2 confirmed
  if (status === 2) return { orgUserId, confirmed: false };
  if (status === 0) throw new Error(
    'member is stuck in Invited state — expected auto-accept with SMTP disabled; check server config',
  );
  const userId = field(entry, 'userId');
  const pub = await api('GET', `/api/users/${userId}/public-key`, { token: cg.token });
  if (!pub.ok) fail('member public key', pub);
  const memberPubDer = Buffer.from(field(pub.data, 'publicKey'), 'base64');
  const confirm = await api('POST', `/api/organizations/${org.orgId}/users/${orgUserId}/confirm`, {
    token: cg.token,
    json: { key: rsaWrap4(memberPubDer, org.orgKey) },
  });
  if (!confirm.ok) fail('confirm member', confirm);
  return { orgUserId, confirmed: true };
}

// ------------------------------------------------------------------- main

const cmd = process.argv[2];
if (cmd !== 'setup') {
  console.error('usage: node register-helper.mjs setup');
  process.exit(2);
}

const cg = await ensureAccount(CAREGIVER);
console.error(`caregiver ${CAREGIVER.email}: ${cg.created ? 'registered' : 'exists'}`);
const mem = await ensureAccount(MEMBER);
console.error(`member ${MEMBER.email}: ${mem.created ? 'registered' : 'exists'}`);
const org = await ensureOrg(cg);
console.error(`org "${ORG_NAME}" ${org.orgId}, collection "${COLLECTION_NAME}" ${org.collectionId}`);
const ms = await ensureMembership(cg, org, MEMBER.email);
console.error(`membership ${ms.orgUserId}${ms.confirmed ? ' (confirmed now)' : ''}`);

for (const [k, v] of Object.entries({
  AMPARO_VW_URL: VW_URL,
  CAREGIVER_EMAIL: CAREGIVER.email,
  CAREGIVER_PASSWORD: CAREGIVER.password,
  MEMBER_EMAIL: MEMBER.email,
  MEMBER_PASSWORD: MEMBER.password,
  ORG_ID: org.orgId,
  COLLECTION_ID: org.collectionId,
  MEMBER_ORG_USER_ID: ms.orgUserId,
})) console.log(`${k}=${v}`);
