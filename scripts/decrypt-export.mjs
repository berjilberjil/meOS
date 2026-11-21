#!/usr/bin/env node
/**
 * Decrypt a MeOS encrypted JSON backup created by the native app
 * (Settings → Export encrypted backup).
 *
 * Usage:
 *   MEOS_EXPORT_PASSPHRASE='the backup passphrase' \
 *     node scripts/decrypt-export.mjs MeOS-backup.meosenc.json > restored.json
 *
 * This only decrypts the portable JSON export. A full MeOS restore also needs
 * the R2 media (not embedded) and a deliberate import into a running app.
 */
import { createDecipheriv, pbkdf2Sync } from 'node:crypto';
import { readFileSync } from 'node:fs';

const path = process.argv[2];
const passphrase = process.env.MEOS_EXPORT_PASSPHRASE;
if (!path || !passphrase) {
  console.error('Usage: MEOS_EXPORT_PASSPHRASE=... node scripts/decrypt-export.mjs <file.meosenc.json>');
  process.exit(1);
}

let env;
try {
  env = JSON.parse(readFileSync(path, 'utf8'));
} catch {
  console.error('That file is not valid JSON.');
  process.exit(1);
}
if (env.format !== 'meos-encrypted-export' || env.kdf !== 'pbkdf2-sha256') {
  console.error('That is not a MeOS encrypted export.');
  process.exit(1);
}
const iterations = Number(env.iterations);
if (!Number.isInteger(iterations) || iterations < 100_000 || iterations > 2_000_000) {
  console.error('Refusing an unexpected KDF work factor.');
  process.exit(1);
}

const salt = Buffer.from(String(env.salt), 'base64');
const combined = Buffer.from(String(env.ct), 'base64');
if (salt.length < 16 || combined.length < 28) {
  console.error('The envelope is malformed.');
  process.exit(1);
}
const key = pbkdf2Sync(Buffer.from(passphrase.normalize('NFC'), 'utf8'), salt, iterations, 32, 'sha256');
const iv = combined.subarray(0, 12);
const tag = combined.subarray(combined.length - 16);
const ct = combined.subarray(12, combined.length - 16);
const decipher = createDecipheriv('aes-256-gcm', key, iv, { authTagLength: 16 });
decipher.setAAD(Buffer.from('meos.export.v1', 'utf8'));
decipher.setAuthTag(tag);
try {
  const plain = Buffer.concat([decipher.update(ct), decipher.final()]);
  process.stdout.write(plain);
} catch {
  console.error('Wrong passphrase, or the backup is corrupt.');
  process.exit(1);
}
