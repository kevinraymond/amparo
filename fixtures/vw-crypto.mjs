// amparo fixtures — shared §6 crypto (docs/amparo-handoff.md, written from
// public documentation; see CLEANROOM.md). Node stdlib only. Dev tooling —
// NOT the clean-room iOS implementation; doubles as the behavioral
// test-vector source for AmparoKit.

import crypto from 'node:crypto';

// §6.1 Master Key: PBKDF2-SHA256(password, salt=lowercase email), 32 bytes.
export const masterKey = (email, password, iterations) =>
  crypto.pbkdf2Sync(Buffer.from(password, 'utf8'), Buffer.from(email, 'utf8'), iterations, 32, 'sha256');

// §6.1 Master Password Hash: PBKDF2-SHA256(masterKey, salt=password, 1 iter).
export const masterPasswordHash = (mk, password) =>
  crypto.pbkdf2Sync(mk, Buffer.from(password, 'utf8'), 1, 32, 'sha256').toString('base64');

// §6.1 HKDF-Expand only (RFC 5869 §2.3), PRK = masterKey.
export function hkdfExpand(prk, info, length) {
  const out = [];
  let t = Buffer.alloc(0);
  for (let i = 1; out.reduce((n, b) => n + b.length, 0) < length; i++) {
    t = crypto.createHmac('sha256', prk)
      .update(Buffer.concat([t, Buffer.from(info, 'utf8'), Buffer.from([i])]))
      .digest();
    out.push(t);
  }
  return Buffer.concat(out).subarray(0, length);
}

// 64-byte symmetric key convention: first 32 = enc, last 32 = mac (§6.1).
export const splitKey = (key64) => ({ enc: key64.subarray(0, 32), mac: key64.subarray(32, 64) });
export const stretchMasterKey = (mk) => ({ enc: hkdfExpand(mk, 'enc', 32), mac: hkdfExpand(mk, 'mac', 32) });

// §6.2 EncString type 2: AES-256-CBC + HMAC-SHA256 over iv‖ct.
export function encString2({ enc, mac }, plaintext) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', enc, iv); // PKCS#7 by default
  const ct = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = crypto.createHmac('sha256', mac).update(Buffer.concat([iv, ct])).digest();
  return `2.${iv.toString('base64')}|${ct.toString('base64')}|${tag.toString('base64')}`;
}

export function decString2({ enc, mac }, encString) {
  const [type, rest] = [encString.slice(0, 1), encString.slice(2)];
  if (type !== '2') throw new Error(`expected EncString type 2, got ${encString.slice(0, 2)}`);
  const [iv, ct, tag] = rest.split('|').map((p) => Buffer.from(p, 'base64'));
  const expect = crypto.createHmac('sha256', mac).update(Buffer.concat([iv, ct])).digest();
  if (!crypto.timingSafeEqual(tag, expect)) throw new Error('EncString MAC mismatch');
  const decipher = crypto.createDecipheriv('aes-256-cbc', enc, iv);
  return Buffer.concat([decipher.update(ct), decipher.final()]);
}

// §6.2 EncString type 4: RSA-2048-OAEP-SHA1.
export const rsaWrap4 = (publicKeySpkiDer, data) =>
  '4.' + crypto.publicEncrypt(
    {
      key: crypto.createPublicKey({ key: publicKeySpkiDer, format: 'der', type: 'spki' }),
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: 'sha1',
    },
    data,
  ).toString('base64');

export function rsaUnwrap(privateKeyPkcs8Der, encString) {
  const dot = encString.indexOf('.');
  const type = encString.slice(0, dot);
  if (type !== '4' && type !== '3') throw new Error(`expected RSA EncString, got type ${type}`);
  return crypto.privateDecrypt(
    {
      key: crypto.createPrivateKey({ key: privateKeyPkcs8Der, format: 'der', type: 'pkcs8' }),
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: type === '4' ? 'sha1' : 'sha256',
    },
    Buffer.from(encString.slice(dot + 1).split('|')[0], 'base64'),
  );
}

export const newRsaPair = () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  return {
    publicDer: publicKey.export({ format: 'der', type: 'spki' }),
    privateDer: privateKey.export({ format: 'der', type: 'pkcs8' }),
  };
};

export const ownPublicDer = (privateKeyPkcs8Der) =>
  crypto.createPublicKey(
    crypto.createPrivateKey({ key: privateKeyPkcs8Der, format: 'der', type: 'pkcs8' }),
  ).export({ format: 'der', type: 'spki' });
